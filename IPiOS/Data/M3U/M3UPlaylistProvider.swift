import Foundation

/// M3U / M3U8 playlist kaynağı için `PlaylistProviding` implementasyonu.
///
/// M3U formatında içerik türü açıkça belirtilmez; bu yüzden kanal / film / dizi
/// ayrımı sezgisel olarak yapılır (bkz. `ContentClassifier`). Sınıflandırma
/// sonucu `PlaylistCache` içinde saklanır, liste yalnızca bir kez ayrıştırılır.
final class M3UPlaylistProvider: PlaylistProviding, @unchecked Sendable {

    private let source: PlaylistSource
    private let network: NetworkClient
    private let localFileURL: URL?
    private let cache: PlaylistCache

    /// - Parameters:
    ///   - source: M3U kaynağının tanımı.
    ///   - localFileURL: Kullanıcının dosya olarak içe aktardığı playlist.
    ///   - network: Ağ istemcisi.
    init(
        source: PlaylistSource,
        localFileURL: URL? = nil,
        network: NetworkClient = NetworkClient()
    ) {
        self.source = source
        self.localFileURL = localFileURL
        self.network = network
        self.cache = PlaylistCache(sourceID: source.id)
    }

    var sourceID: UUID { source.id }

    // MARK: - PlaylistProviding

    func validate() async throws -> SourceInfo {
        let result = try await loadParsed()
        guard !result.isEmpty else { throw AppError.playlistEmpty }

        let classified = ContentClassifier.classify(result.entries, sourceID: source.id)
        return SourceInfo(
            status: "Active",
            expiresAt: nil,
            maxConnections: nil,
            createdAt: nil,
            liveCount: classified.channels.count,
            movieCount: classified.movies.count,
            seriesCount: classified.series.count
        )
    }

    func categories(kind: CategoryKind) async throws -> [Category] {
        let items = try await allItems()
        let names: [String]
        switch kind {
        case .live: names = items.channels.compactMap(\.categoryName)
        case .movie: names = items.movies.compactMap(\.categoryName)
        case .series: names = items.series.compactMap(\.categoryName)
        }

        var seen = Set<String>()
        var ordered: [String] = []
        for name in names where !seen.contains(name) {
            seen.insert(name)
            ordered.append(name)
        }

        // M3U'da kategori kimliği yoktur; isim hem id hem ad olarak kullanılır.
        let counts: [String: Int] = names.reduce(into: [:]) { $0[$1, default: 0] += 1 }

        return ordered.enumerated().map { index, name in
            Category(id: name, name: name, kind: kind, order: index, itemCount: counts[name])
        }
    }

    func channels(categoryID: String?) async throws -> [Channel] {
        let items = try await allItems()
        guard let categoryID, !categoryID.isEmpty else { return items.channels }
        return items.channels.filter { $0.categoryName == categoryID }
    }

    func movies(categoryID: String?) async throws -> [Movie] {
        let items = try await allItems()
        guard let categoryID, !categoryID.isEmpty else { return items.movies }
        return items.movies.filter { $0.categoryName == categoryID }
    }

    func seriesList(categoryID: String?) async throws -> [Series] {
        let items = try await allItems()
        guard let categoryID, !categoryID.isEmpty else { return items.series }
        return items.series.filter { $0.categoryName == categoryID }
    }

    /// M3U playlistlerinde bölüm bilgisi ayrı gelmediği için, aynı dizinin
    /// bölümleri `group-title` ile gruplanır. Bölüm numarası başlıktan çıkarılır.
    func seriesDetail(seriesID: String) async throws -> SeriesDetail {
        let items = try await allItems()
        guard let series = items.series.first(where: { $0.id == seriesID }) else {
            throw AppError.notFound
        }

        let playlist = try await loadParsed()
        let group = series.categoryName

        // Aynı gruptaki kayıtları bölüm olarak değerlendir.
        let candidates = playlist.entries.filter { entry in
            entry.effectiveGroup == group && !ContentClassifier.looksLikeMovie(entry)
        }

        var episodes: [Episode] = candidates.enumerated().map { index, entry in
            let url = entry.url
            let parsed = ContentClassifier.parseSeasonEpisode(entry.effectiveTitle)
            return Episode(
                id: "\(seriesID)-\(index)",
                sourceID: source.id,
                seriesID: seriesID,
                seasonNumber: parsed?.season ?? 1,
                episodeNumber: parsed?.episode ?? (index + 1),
                title: entry.effectiveTitle,
                imageURL: entry.logoURL,
                streamURL: url,
                plot: nil,
                durationSeconds: nil
            )
        }

        // Bölüm bulunamazsa dizinin kendisi tek bölüm olarak sunulur.
        if episodes.isEmpty, let first = candidates.first {
            episodes = [
                Episode(
                    id: "\(seriesID)-0",
                    sourceID: source.id,
                    seriesID: seriesID,
                    seasonNumber: 1,
                    episodeNumber: 1,
                    title: first.effectiveTitle,
                    imageURL: first.logoURL,
                    streamURL: first.url,
                    plot: nil,
                    durationSeconds: nil
                )
            ]
        }

        let seasonNumbers = Set(episodes.map(\.seasonNumber))
        let seasons = seasonNumbers.sorted().map { number in
            Season(number: number, episodes: episodes.filter { $0.seasonNumber == number })
        }

        return SeriesDetail(series: series, seasons: seasons)
    }

    /// Playlist dosyasını yeniden indirmeye zorlar.
    func invalidate() async {
        await cache.invalidate()
    }

    // MARK: - Private

    private func allItems() async throws -> Classified {
        if let cached = await cache.classified() {
            return cached
        }
        let parsed = try await loadParsed()
        guard !parsed.isEmpty else { throw AppError.playlistEmpty }
        let classified = ContentClassifier.classify(parsed.entries, sourceID: source.id)
        await cache.store(classified)
        return classified
    }

    private func loadParsed() async throws -> M3UParser.Result {
        if let cached = await cache.parsed() {
            return cached
        }

        let text: String
        if let localFileURL {
            text = try readLocalFile(localFileURL)
        } else {
            text = try await network.getString(from: source.baseURL)
        }

        let parsed = M3UParser.parse(text)
        await cache.store(parsed)
        return parsed
    }

    private func readLocalFile(_ url: URL) throws -> String {
        let needsRelease = url.startAccessingSecurityScopedResource()
        defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let latin = String(data: data, encoding: .isoLatin1) { return latin }
        throw AppError.playlistEmpty
    }
}

// MARK: - Önbellek

/// Playlist metnini ve sınıflandırılmış içeriği oturum boyunca saklar.
private actor PlaylistCache {
    private var parsedResult: M3UParser.Result?
    private var classifiedItems: Classified?

    init(sourceID: UUID) {}

    func parsed() -> M3UParser.Result? { parsedResult }
    func classified() -> Classified? { classifiedItems }

    func store(_ result: M3UParser.Result) { parsedResult = result }
    func store(_ items: Classified) { classifiedItems = items }

    func invalidate() {
        parsedResult = nil
        classifiedItems = nil
    }
}

/// M3U kayıtlarının içerik türüne göre ayrılmış hali.
struct Classified {
    var channels: [Channel]
    var movies: [Movie]
    var series: [Series]
}

// MARK: - İçerik sınıflandırma

/// M3U kayıtlarını kanal / film / dizi olarak ayırır.
///
/// M3U standardı içerik türünü taşımadığı için iki sinyal kullanılır:
/// grup adındaki anahtar kelimeler ve akış adresinin uzantısı.
enum ContentClassifier {

    private static let movieKeywords = [
        "film", "movie", "vod", "sinema", "cinema", "box office", "yabanci film", "yerli film"
    ]

    private static let seriesKeywords = [
        "dizi", "series", "show", "sezon", "season", "episode", "bolum", "bölüm"
    ]

    /// VOD kabul edilen dosya uzantıları.
    private static let vodExtensions: Set<String> = ["mp4", "mkv", "avi", "mov", "webm", "m4v"]

    static func classify(_ entries: [M3UParser.Entry], sourceID: UUID) -> Classified {
        var channels: [Channel] = []
        var movies: [Movie] = []
        var series: [Series] = []

        for entry in entries {
            let group = entry.effectiveGroup
            let title = entry.effectiveTitle

            if looksLikeSeries(entry), let group {
                series.append(
                    Series(
                        id: group,
                        sourceID: sourceID,
                        title: group,
                        imageURL: entry.logoURL,
                        categoryName: group,
                        order: entry.index
                    )
                )
            } else if looksLikeMovie(entry) {
                movies.append(
                    Movie(
                        id: entry.url.absoluteString,
                        sourceID: sourceID,
                        title: title,
                        imageURL: entry.logoURL,
                        streamURL: entry.url,
                        categoryName: group,
                        containerExtension: entry.url.pathExtension,
                        order: entry.index
                    )
                )
            } else {
                channels.append(
                    Channel(
                        id: entry.tvgID ?? entry.url.absoluteString,
                        sourceID: sourceID,
                        title: title,
                        imageURL: entry.logoURL,
                        streamURL: entry.url,
                        categoryName: group,
                        epgChannelID: entry.tvgID,
                        order: entry.index
                    )
                )
            }
        }

        // Aynı grup adına sahip birden fazla dizi kaydı tek diziye indirgenir.
        var uniqueSeries: [Series] = []
        var seenSeriesIDs = Set<String>()
        for item in series where !seenSeriesIDs.contains(item.id) {
            seenSeriesIDs.insert(item.id)
            uniqueSeries.append(item)
        }

        return Classified(channels: channels, movies: movies, series: uniqueSeries)
    }

    static func looksLikeMovie(_ entry: M3UParser.Entry) -> Bool {
        let group = (entry.effectiveGroup ?? "").lowercased()
        let urlPath = entry.url.path.lowercased()
        let ext = entry.url.pathExtension.lowercased()

        if movieKeywords.contains(where: { group.contains($0) }) { return true }
        // Uzantı VOD'u işaret ediyorsa ve grup dizi demiyorsa film kabul edilir.
        if vodExtensions.contains(ext), !seriesKeywords.contains(where: { group.contains($0) }) {
            return true
        }
        // "/movie/" yol deseni yaygın bir işarettir.
        if urlPath.contains("/movie/") || urlPath.contains("/vod/") { return true }
        return false
    }

    static func looksLikeSeries(_ entry: M3UParser.Entry) -> Bool {
        let group = (entry.effectiveGroup ?? "").lowercased()
        return seriesKeywords.contains { group.contains($0) }
    }

    /// "Dizi Adı S02E05" veya "2x05" gibi başlıklardan sezon/bölüm çıkarır.
    static func parseSeasonEpisode(_ title: String) -> (season: Int, episode: Int)? {
        // S02E05 / s2e5
        if let match = title.range(
            of: #"[Ss](\d{1,2})\s*[Ee](\d{1,3})"#,
            options: .regularExpression
        ) {
            let text = String(title[match])
            let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap(Int.init)
            if numbers.count >= 2 {
                return (numbers[0], numbers[1])
            }
        }

        // 2x05
        if let match = title.range(
            of: #"(\d{1,2})\s*[xX]\s*(\d{1,3})"#,
            options: .regularExpression
        ) {
            let numbers = String(title[match])
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap(Int.init)
            if numbers.count >= 2 {
                return (numbers[0], numbers[1])
            }
        }

        return nil
    }
}
