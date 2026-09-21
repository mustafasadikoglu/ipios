import Foundation

/// Xtream Codes API istemcisi.
///
/// Tüm istekler `player_api.php` üzerinden yapılır ve `username` + `password`
/// query parametresi olarak gönderilir. Şifre yalnızca bellek içinde tutulur;
/// diske yazılmaz (Keychain'de saklanır, bkz. `PlaylistSource`).
final class XtreamClient: PlaylistProviding, @unchecked Sendable {

    private let source: PlaylistSource
    private let password: String
    private let network: NetworkClient

    // Aynı oturumda tekrar tekrar çekilmemesi için basit bellek önbelleği.
    private let cache = ResponseCache()

    init(source: PlaylistSource, password: String, network: NetworkClient = NetworkClient()) {
        self.source = source
        self.password = password
        self.network = network
    }

    var sourceID: UUID { source.id }

    // MARK: - PlaylistProviding

    func validate() async throws -> SourceInfo {
        let auth: XtreamDTO.AuthResponse = try await request(action: nil)
        if let error = auth.error, !error.isEmpty {
            throw AppError.badCredentials
        }
        guard let userInfo = auth.user_info else {
            throw AppError.badCredentials
        }
        let status = userInfo.status
        if let status, status.lowercased() != "active" {
            throw AppError.badCredentials
        }

        return SourceInfo(
            status: status,
            expiresAt: Self.parseTimestamp(userInfo.exp_date),
            maxConnections: Int(userInfo.max_connections ?? ""),
            createdAt: Self.parseTimestamp(userInfo.created_at),
            liveCount: nil,
            movieCount: nil,
            seriesCount: nil
        )
    }

    func categories(kind: CategoryKind) async throws -> [Category] {
        let list: [XtreamDTO.CategoryDTO] = try await request(action: Self.categoryAction(kind))
        return list.enumerated().compactMap { index, dto in
            guard let id = dto.category_id?.stringValue else { return nil }
            let name = dto.category_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Category(
                id: id,
                name: (name?.isEmpty == false ? name! : L.f("fallback.category", id)),
                kind: kind,
                order: index
            )
        }
    }

    func channels(categoryID: String?) async throws -> [Channel] {
        let list: [XtreamDTO.LiveStreamDTO] = try await request(action: "get_live_streams")
        let categories = try? await categories(kind: .live)
        let nameByID = Dictionary(uniqueKeysWithValues: (categories ?? []).map { ($0.id, $0.name) })

        return list.enumerated().compactMap { index, dto -> Channel? in
            guard let id = dto.stream_id?.stringValue else { return nil }
            let catID = dto.category_id?.stringValue
            if let categoryID, let catID, catID != categoryID { return nil }

            let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let streamURL = makeStreamURL(
                streamID: id,
                type: "live",
                extensionHint: dto.stream_type
            ) else { return nil }

            return Channel(
                id: id,
                sourceID: source.id,
                title: (name?.isEmpty == false ? name! : L.f("fallback.channel", id)),
                imageURL: dto.stream_icon.flatMap(URL.init(string:)),
                streamURL: streamURL,
                categoryID: catID,
                categoryName: catID.flatMap { nameByID[$0] },
                hasArchive: (dto.tv_archive?.intValue ?? 0) == 1,
                epgChannelID: dto.epg_channel_id,
                order: dto.num?.intValue ?? index
            )
        }
    }

    func movies(categoryID: String?) async throws -> [Movie] {
        let list: [XtreamDTO.VODStreamDTO] = try await request(action: "get_vod_streams")
        let categories = try? await categories(kind: .movie)
        let nameByID = Dictionary(uniqueKeysWithValues: (categories ?? []).map { ($0.id, $0.name) })

        return list.enumerated().compactMap { index, dto -> Movie? in
            guard let id = dto.stream_id?.stringValue else { return nil }
            let catID = dto.category_id?.stringValue
            if let categoryID, let catID, catID != categoryID { return nil }

            let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let ext = dto.container_extension ?? "mp4"
            guard let streamURL = makeStreamURL(streamID: id, type: "movie", extensionHint: ext) else {
                return nil
            }

            return Movie(
                id: id,
                sourceID: source.id,
                title: (name?.isEmpty == false ? name! : L.f("fallback.movie", id)),
                imageURL: dto.stream_icon.flatMap(URL.init(string:)),
                streamURL: streamURL,
                categoryID: catID,
                categoryName: catID.flatMap { nameByID[$0] },
                plot: dto.plot?.nilIfEmpty,
                year: dto.year?.stringValue.nilIfEmpty
                    ?? dto.releaseDate?.nilIfEmpty.map { String($0.prefix(4)) },
                durationSeconds: Self.parseDuration(dto.duration?.nonEmpty),
                rating: dto.rating?.nonEmpty,
                genre: dto.genre?.nilIfEmpty,
                containerExtension: dto.container_extension,
                order: dto.num?.intValue ?? index
            )
        }
    }

    func seriesList(categoryID: String?) async throws -> [Series] {
        let list: [XtreamDTO.SeriesDTO] = try await request(action: "get_series")
        let categories = try? await categories(kind: .series)
        let nameByID = Dictionary(uniqueKeysWithValues: (categories ?? []).map { ($0.id, $0.name) })

        return list.enumerated().compactMap { index, dto -> Series? in
            guard let id = dto.series_id?.stringValue else { return nil }
            let catID = dto.category_id?.stringValue
            if let categoryID, let catID, catID != categoryID { return nil }

            let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Series(
                id: id,
                sourceID: source.id,
                title: (name?.isEmpty == false ? name! : L.f("fallback.series", id)),
                imageURL: dto.cover.flatMap(URL.init(string:)),
                categoryID: catID,
                categoryName: catID.flatMap { nameByID[$0] },
                plot: dto.plot?.nilIfEmpty,
                year: dto.releaseDate?.nonEmpty.map { String($0.prefix(4)) },
                rating: dto.rating?.nonEmpty,
                genre: dto.genre?.nilIfEmpty,
                lastModified: Self.parseTimestamp(dto.last_modified?.nonEmpty),
                order: dto.num?.intValue ?? index
            )
        }
    }

    func seriesDetail(seriesID: String) async throws -> SeriesDetail {
        let response: XtreamDTO.SeriesInfoResponse = try await request(
            action: "get_series_info",
            extra: ["series_id": seriesID]
        )

        // Dizi başlığı: bilgi varsa ondan, yoksa listeden bulunur.
        let title = response.info?.name?.nilIfEmpty ?? L.f("fallback.series", seriesID)
        let series = Series(
            id: seriesID,
            sourceID: source.id,
            title: title,
            imageURL: response.info?.cover.flatMap(URL.init(string:)),
            plot: response.info?.plot?.nilIfEmpty,
            year: response.info?.releaseDate?.nonEmpty.map { String($0.prefix(4)) },
            rating: response.info?.rating?.nonEmpty,
            genre: response.info?.genre?.nilIfEmpty
        )

        // `episodes` sözlüğü: sezon numarası (string) -> bölüm dizisi.
        var seasons: [Season] = []
        for (seasonKey, episodeDTOs) in response.episodes ?? [:] {
            guard let seasonNumber = Int(seasonKey) else { continue }

            let episodes: [Episode] = episodeDTOs.compactMap { dto in
                guard let id = dto.id?.stringValue else { return nil }
                let ext = dto.container_extension ?? "mp4"
                guard let streamURL = makeStreamURL(
                    streamID: id,
                    type: "series",
                    extensionHint: ext
                ) else { return nil }

                return Episode(
                    id: id,
                    sourceID: source.id,
                    seriesID: seriesID,
                    seasonNumber: dto.season?.intValue ?? seasonNumber,
                    episodeNumber: dto.episode_num?.intValue ?? 0,
                    title: dto.title?.nilIfEmpty ?? "",
                    imageURL: (dto.info?.movie_image ?? response.info?.cover).flatMap(URL.init(string:)),
                    streamURL: streamURL,
                    plot: dto.info?.plot?.nilIfEmpty,
                    durationSeconds: Self.parseDuration(dto.info?.duration?.nonEmpty)
                )
            }
            .sorted { $0.episodeNumber < $1.episodeNumber }

            guard !episodes.isEmpty else { continue }
            seasons.append(Season(number: seasonNumber, episodes: episodes))
        }

        seasons.sort { $0.number < $1.number }
        return SeriesDetail(series: series, seasons: seasons)
    }

    // MARK: - EPG (kısa liste)

    /// Xtream'in `get_short_epg` endpoint'inden bir kanalın kısa yayın akışını çeker.
    /// Geniş XMLTV verisi yoksa bu hafif yol kullanılır.
    func shortEPG(streamID: String, limit: Int = 6) async throws -> [EPGProgram] {
        let response: XtreamDTO.ShortEPGResponse = try await request(
            action: "get_short_epg",
            extra: ["stream_id": streamID, "limit": String(limit)]
        )

        return (response.epg_listings ?? []).compactMap { listing -> EPGProgram? in
            let title = listing.title?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .decodedBase64IfNeeded
            guard let title, !title.isEmpty else { return nil }

            guard let start = Self.parseEPGDate(listing.start_timestamp?.stringValue ?? listing.start),
                  let end = Self.parseEPGDate(listing.stop_timestamp?.stringValue ?? listing.end) else {
                return nil
            }

            return EPGProgram(
                id: listing.id?.stringValue ?? UUID().uuidString,
                channelID: listing.channel_id ?? listing.epg_id?.stringValue ?? streamID,
                title: title,
                description: listing.description?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .decodedBase64IfNeeded,
                start: start,
                end: end
            )
        }
        .sorted { $0.start < $1.start }
    }

    // MARK: - Özel URL'ler

    /// XMLTV EPG adresi (Xtream standart yolu).
    var xmltvURL: URL? {
        var components = URLComponents(url: source.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/xmltv.php"
        components?.queryItems = credentialsQueryItems
        return components?.url
    }

    /// Ham M3U playlist adresi (Xtream `get.php` yolu).
    func m3uURL(includeVOD: Bool = true) -> URL? {
        var components = URLComponents(url: source.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/get.php"
        var items = credentialsQueryItems
        items.append(URLQueryItem(name: "type", value: "m3u_plus"))
        items.append(URLQueryItem(name: "output", value: includeVOD ? "ts" : "hls"))
        components?.queryItems = items
        return components?.url
    }

    // MARK: - Private

    private var credentialsQueryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let username = source.username {
            items.append(URLQueryItem(name: "username", value: username))
        }
        items.append(URLQueryItem(name: "password", value: password))
        return items
    }

    private static func categoryAction(_ kind: CategoryKind) -> String {
        switch kind {
        case .live: return "get_live_categories"
        case .movie: return "get_vod_categories"
        case .series: return "get_series_categories"
        }
    }

    /// `player_api.php` isteğini kurar ve çözer.
    ///
    /// - Note: `action == nil` ise kimlik doğrulama isteği yapılır.
    private func request<T: Decodable>(
        action: String?,
        extra: [String: String] = [:]
    ) async throws -> T {
        guard let url = buildAPIURL(action: action, extra: extra) else {
            throw AppError.invalidURL
        }

        let cacheKey = url.absoluteString
        if let cached: T = await cache.value(for: cacheKey) {
            return cached
        }

        do {
            let result: T = try await network.getJSON(T.self, from: url)
            await cache.store(result, for: cacheKey)
            return result
        } catch let error as AppError {
            // Xtream yanlış kimlik bilgisinde bazen HTTP 200 + `{"user_info":...}` yerine
            // boş gövde döner; bunu kimlik hatası olarak raporlarız.
            if case .decoding = error {
                throw AppError.badCredentials
            }
            throw error
        }
    }

    private func buildAPIURL(action: String?, extra: [String: String]) -> URL? {
        var components = URLComponents(url: source.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/player_api.php"
        var items = credentialsQueryItems
        if let action {
            items.append(URLQueryItem(name: "action", value: action))
        }
        for (key, value) in extra {
            items.append(URLQueryItem(name: key, value: value))
        }
        components?.queryItems = items
        return components?.url
    }

    /// Xtream akış adreslerini üretir.
    ///
    /// - live:   `/live/<user>/<pass>/<id>.<ext>`
    /// - movie:  `/movie/<user>/<pass>/<id>.<ext>`
    /// - series: `/series/<user>/<pass>/<id>.<ext>`
    private func makeStreamURL(streamID: String, type: String, extensionHint: String?) -> URL? {
        guard let username = source.username else { return nil }
        let ext = Self.normalizeExtension(extensionHint)

        var components = URLComponents(url: source.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/\(type)/\(username)/\(password)/\(streamID).\(ext)"
        components?.queryItems = nil
        return components?.url
    }

    /// `m3u8`/`ts`/`mp4` gibi uzantıyı normalize eder.
    static func normalizeExtension(_ hint: String?) -> String {
        guard let hint = hint?.lowercased(), !hint.isEmpty else { return "m3u8" }
        switch hint {
        case "m3u8", "hls": return "m3u8"
        case "ts", "mpegts": return "ts"
        case "mp4", "mkv", "avi", "mov", "webm": return hint
        default: return hint.replacingOccurrences(of: ".", with: "")
        }
    }

    // MARK: - Tarih / süre çözümleme

    /// Xtream tarihleri genellikle Unix zaman damgasıdır ("1700000000"),
    /// bazen "2024-05-01 12:00:00" biçiminde gelir.
    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let interval = TimeInterval(raw) {
            // Saniye cinsinden zaman damgası (milisaniye değil).
            return Date(timeIntervalSince1970: interval > 1e11 ? interval / 1000 : interval)
        }
        return dateTimeFormatter.date(from: raw)
            ?? isoFormatter.date(from: raw)
    }

    static func parseEPGDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let interval = TimeInterval(raw), interval > 1_000_000 {
            return Date(timeIntervalSince1970: interval)
        }
        return dateTimeFormatter.date(from: raw) ?? isoFormatter.date(from: raw)
    }

    /// "01:52:30" veya "112 min" gibi süreleri saniyeye çevirir.
    static func parseDuration(_ raw: String?) -> Double? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        // "HH:MM:SS" veya "MM:SS"
        if raw.contains(":") {
            let parts = raw.split(separator: ":").compactMap { Double($0) }
            switch parts.count {
            case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
            case 2: return parts[0] * 60 + parts[1]
            default: return nil
            }
        }

        // "112 min" / "112 dk"
        let lowered = raw.lowercased()
        if lowered.contains("min") || lowered.contains("dk") {
            let numericPart = String(raw.prefix { $0.isNumber || $0 == "." || $0 == "," })
                .replacingOccurrences(of: ",", with: ".")
            if let value = Double(numericPart), value > 0 {
                return value * 60
            }
        }

        // Sadece sayı: saniye kabul edilir.
        if let seconds = Double(raw), seconds > 0 {
            return seconds
        }
        return nil
    }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Yanıt önbelleği

/// Aynı oturumda tekrarlanan Xtream isteklerini engelleyen basit önbellek.
/// (Kanallar, kategoriler ve filmler için tip bazlı.)
private actor ResponseCache {
    private var storage: [String: Any] = [:]

    func value<T>(for key: String) -> T? {
        storage[key] as? T
    }

    func store<T>(_ value: T, for key: String) {
        storage[key] = value
    }

    func clear() {
        storage.removeAll()
    }
}

// MARK: - Küçük yardımcılar

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Xtream EPG başlıkları bazen Base64 kodlanmış gelir.
    var decodedBase64IfNeeded: String {
        // Uzunluk 4'ün katı ve yalnızca Base64 karakterleriyse kod çözülür.
        let base64Chars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        guard count >= 8,
              count % 4 == 0,
              unicodeScalars.allSatisfy({ base64Chars.contains($0) }),
              let data = Data(base64Encoded: self),
              let decoded = String(data: data, encoding: .utf8),
              !decoded.isEmpty else {
            return self
        }
        return decoded
    }
}
