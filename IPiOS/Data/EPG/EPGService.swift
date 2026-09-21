import Foundation

/// XMLTV tabanlı EPG servisi.
///
/// Akış:
/// 1. XMLTV dosyası diske indirilir (veya Xtream'in `xmltv.php` yolu kullanılır).
/// 2. Yalnızca istenen kanallar filtrelenerek ayrıştırılır.
/// 3. Sonuç kanal bazında JSON dosyalarına parçalanır; sonraki açılışlarda
///    yüz megabaytlık XML yeniden ayrıştırılmaz.
///
/// Dosyalar `Application Support/EPG/` altında `epg-<channelID>.json` olarak durur.
final class EPGService: EPGProviding, @unchecked Sendable {

    private let sourceID: UUID
    private let remoteURL: URL?
    private let network: NetworkClient
    private let store: JSONFileStore
    private let workingDirectory: URL

    /// Aynı kanal için tekrar tekrar disk okumasını engelleyen bellek önbelleği.
    private let memoryCache = EPGMemoryCache()

    /// EPG verisinin geçerlilik süresi. Bu süre geçtiyse uzak kaynaktan yenilenir.
    private let freshness: TimeInterval

    init(
        sourceID: UUID,
        remoteURL: URL?,
        network: NetworkClient = NetworkClient(),
        freshness: TimeInterval = 6 * 3600
    ) {
        self.sourceID = sourceID
        self.remoteURL = remoteURL
        self.network = network
        self.freshness = freshness
        self.store = JSONFileStore(folderName: "EPG")

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("EPGCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.workingDirectory = dir
    }

    // MARK: - EPGProviding

    func programs(for channelIDs: [String], horizon: TimeInterval) async throws -> [String: [EPGProgram]] {
        guard !channelIDs.isEmpty else { return [:] }

        var result: [String: [EPGProgram]] = [:]
        var missing: [String] = []

        for channelID in channelIDs {
            if let cached = await memoryCache.programs(for: channelID) {
                result[channelID] = filterByHorizon(cached, horizon: horizon)
            } else if let stored = try? await store.load([EPGProgram].self, from: fileName(for: channelID)) {
                await memoryCache.set(stored, for: channelID)
                result[channelID] = filterByHorizon(stored, horizon: horizon)
            } else {
                missing.append(channelID)
            }
        }

        // Diskte olmayan kanallar için XMLTV kaynağı bir kez indirilip ayrıştırılır.
        if !missing.isEmpty, remoteURL != nil {
            try await refresh(channelIDs: Set(channelIDs))
            for channelID in missing {
                if let refreshed = await memoryCache.programs(for: channelID) {
                    result[channelID] = filterByHorizon(refreshed, horizon: horizon)
                } else {
                    result[channelID] = []
                }
            }
        }

        return result
    }

    func nowAndNext(channelID: String) async throws -> (now: EPGProgram?, next: EPGProgram?) {
        let programs = try await programs(for: [channelID], horizon: 24 * 3600)[channelID] ?? []
        let sorted = programs.sorted { $0.start < $1.start }
        let now = sorted.first { $0.isLive }
        let next = sorted.first { $0.start > Date() }
        return (now, next)
    }

    func invalidateCache() async {
        await memoryCache.clear()
        try? await store.deleteAll()
        try? FileManager.default.removeItem(at: workingDirectory)
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Yenileme

    /// Uzak XMLTV kaynağını indirir, ayrıştırır ve kanal bazında diske yazar.
    ///
    /// - Parameter channelIDs: Yalnızca bu kanallar saklanır. `nil` ise tümü.
    func refresh(channelIDs: Set<String>?) async throws {
        guard let remoteURL else { return }

        let xmlFile = workingDirectory.appendingPathComponent("epg-\(sourceID.uuidString).xml")

        // Taze dosya varsa yeniden indirmeyiz.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: xmlFile.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < freshness {
            Log.epg.debug("EPG dosyasi taze, indirme atlandi")
        } else {
            Log.epg.info("EPG indiriliyor: \(Log.redacted(remoteURL), privacy: .public)")
            _ = try await network.download(from: remoteURL, to: xmlFile)
        }

        try await parseAndStore(fileAt: xmlFile, filter: channelIDs)
    }

    /// Diskteki XMLTV dosyasını ayrıştırıp kanal bazında JSON'a böler.
    private func parseAndStore(fileAt url: URL, filter: Set<String>?) async throws {
        // Ayrıştırma CPU yoğundur; ana iş parçacığını bloklamamak için
        // ayrı bir görevde çalıştırılır. `XMLTVParser` iş parçacığına bağlı
        // olmayan bir `NSObject` olduğu için örneği görev içinde kurulur.
        let output: XMLTVParser.Output = try await Task.detached(priority: .utility) { [filter] in
            guard let parser = XMLTVParser(contentsOf: url) else {
                throw AppError.notFound
            }
            return parser.parse(filter: filter)
        }.value

        guard !output.programsByChannel.isEmpty else {
            throw AppError.playlistEmpty
        }

        for (channelID, programs) in output.programsByChannel {
            let sorted = programs.sorted { $0.start < $1.start }
            await memoryCache.set(sorted, for: channelID)
            try? await store.save(sorted, as: fileName(for: channelID))
        }

        Log.epg.info("EPG hazir: \(output.programsByChannel.count) kanal, \(output.programCount) program")
    }

    // MARK: - Private

    private func fileName(for channelID: String) -> String {
        // Kanal kimliği dosya adında güvenli olmayan karakter içerebilir.
        let safe = channelID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "epg-\(safe).json"
    }

    private func filterByHorizon(_ programs: [EPGProgram], horizon: TimeInterval) -> [EPGProgram] {
        let now = Date()
        // 2 saat geriye dönük veri de tutulur (catch-up göstergesi için).
        let lowerBound = now.addingTimeInterval(-2 * 3600)
        let upperBound = now.addingTimeInterval(horizon)
        return programs.filter { $0.end > lowerBound && $0.start < upperBound }
    }
}

// MARK: - Bellek önbelleği

private actor EPGMemoryCache {
    private var storage: [String: [EPGProgram]] = [:]

    func programs(for channelID: String) -> [EPGProgram]? {
        storage[channelID]
    }

    func set(_ programs: [EPGProgram], for channelID: String) {
        storage[channelID] = programs
    }

    func clear() {
        storage.removeAll()
    }
}
