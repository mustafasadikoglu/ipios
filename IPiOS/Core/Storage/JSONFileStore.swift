import Foundation

/// `Codable` verileri `Application Support` altında JSON dosyası olarak saklar.
///
/// Atomik yazma kullanılır: yazma sırasında uygulama kapansa bile mevcut
/// dosya bozulmaz.
actor JSONFileStore {

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(folderName: String = "IPiOSData") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = base.appendingPathComponent(folderName, isDirectory: true)

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    func exists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    func save<T: Encodable>(_ value: T, as fileName: String) throws {
        let target = url(for: fileName)
        do {
            let data = try encoder.encode(value)
            try data.write(to: target, options: [.atomic])
            Log.storage.debug("Kaydedildi: \(fileName, privacy: .public) (\(data.count) bayt)")
        } catch {
            Log.storage.error("Kayit hatasi (\(fileName, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            throw AppError.storage(underlying: error.localizedDescription)
        }
    }

    func load<T: Decodable>(_ type: T.Type, from fileName: String) throws -> T? {
        let target = url(for: fileName)
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        do {
            let data = try Data(contentsOf: target)
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.storage.error("Okuma hatasi (\(fileName, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            throw AppError.storage(underlying: error.localizedDescription)
        }
    }

    func delete(_ fileName: String) throws {
        let target = url(for: fileName)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    func deleteAll() throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
    }

    /// Önbelleğin disk üzerindeki toplam boyutu.
    func totalSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: - Private

    private func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }
}
