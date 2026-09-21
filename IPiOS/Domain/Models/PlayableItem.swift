import Foundation

/// Listelerde (canlı, film, dizi, arama, favoriler) taşınan öğe.
///
/// Neden gerekli: arama sonuçları ve favoriler farklı türleri bir arada gösterir.
/// Dizi kaydı **oynatılamaz** (önce sezon/bölüm seçilir), bu yüzden bu enum
/// `MediaItem` protokolüne uymaz; oynatılabilir hâle gelmesi `playable` üzerinden
/// açıkça istenir.
enum PlayableItem: Identifiable, Hashable {

    case channel(Channel)
    case movie(Movie)
    case series(Series)
    case episode(Episode)

    var id: String {
        switch self {
        case .channel(let value): return "live-\(value.id)"
        case .movie(let value): return "movie-\(value.id)"
        case .series(let value): return "series-\(value.id)"
        case .episode(let value): return "episode-\(value.id)"
        }
    }

    var title: String {
        switch self {
        case .channel(let value): return value.title
        case .movie(let value): return value.title
        case .series(let value): return value.title
        case .episode(let value): return value.title
        }
    }

    var imageURL: URL? {
        switch self {
        case .channel(let value): return value.imageURL
        case .movie(let value): return value.imageURL
        case .series(let value): return value.imageURL
        case .episode(let value): return value.imageURL
        }
    }

    var sourceID: UUID {
        switch self {
        case .channel(let value): return value.sourceID
        case .movie(let value): return value.sourceID
        case .series(let value): return value.sourceID
        case .episode(let value): return value.sourceID
        }
    }

    var kind: CategoryKind {
        switch self {
        case .channel: return .live
        case .movie: return .movie
        case .series: return .series
        case .episode: return .series
        }
    }

    /// Oynatılabilir mi? Dizi kayıtları önce detay ekranına gider.
    var isDirectlyPlayable: Bool {
        if case .series = self { return false }
        return true
    }

    /// Oynatıcıya verilecek hâl. Dizi kayıtları için `nil` döner.
    var playable: AnyMediaItem? {
        switch self {
        case .channel(let value):
            return AnyMediaItem(
                id: value.id,
                title: value.title,
                imageURL: value.imageURL,
                streamURL: value.streamURL,
                sourceID: value.sourceID,
                kind: .live,
                contextTitle: value.categoryName,
                detail: nil
            )

        case .movie(let value):
            return AnyMediaItem(
                id: value.id,
                title: value.title,
                imageURL: value.imageURL,
                streamURL: value.streamURL,
                sourceID: value.sourceID,
                kind: .movie,
                contextTitle: value.categoryName,
                detail: value.plot
            )

        case .series:
            return nil

        case .episode(let value):
            return AnyMediaItem(
                id: value.id,
                title: value.fullTitle,
                imageURL: value.imageURL,
                streamURL: value.streamURL,
                sourceID: value.sourceID,
                kind: .series,
                contextTitle: value.title,
                detail: value.plot
            )
        }
    }

    /// Liste alt satırı.
    var subtitle: String? {
        switch self {
        case .channel(let value):
            var parts: [String] = []
            if let category = value.categoryName, !category.isEmpty { parts.append(category) }
            if value.hasArchive { parts.append(L.t("live.badge.archive")) }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")

        case .movie(let value):
            var parts: [String] = []
            if let year = value.year, !year.isEmpty { parts.append(year) }
            if let duration = value.durationText { parts.append(duration) }
            if let genre = value.genre, !genre.isEmpty { parts.append(genre) }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")

        case .series(let value):
            var parts: [String] = []
            if let year = value.year, !year.isEmpty { parts.append(year) }
            if let genre = value.genre, !genre.isEmpty { parts.append(genre) }
            if let category = value.categoryName, !category.isEmpty { parts.append(category) }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")

        case .episode(let value):
            return value.fullTitle
        }
    }

    /// Arama için normalize edilmiş metin.
    var searchText: String {
        switch self {
        case .channel(let value):
            return "\(value.title) \(value.categoryName ?? "")"
        case .movie(let value):
            return "\(value.title) \(value.plot ?? "") \(value.genre ?? "") \(value.year ?? "")"
        case .series(let value):
            return "\(value.title) \(value.plot ?? "") \(value.genre ?? "") \(value.year ?? "")"
        case .episode(let value):
            return "\(value.title) \(value.fullTitle)"
        }
    }

    /// Favorilere eklenebilir mi? Bölümler diziye bağlı olduğu için hariç tutulur.
    var isFavoritable: Bool {
        switch self {
        case .channel, .movie, .series: return true
        case .episode: return false
        }
    }

    /// Favori kaydına dönüştürür (`isFavoritable` ise).
    var reference: MediaReference? {
        switch self {
        case .channel(let value):
            return MediaReference(
                id: value.id,
                sourceID: value.sourceID,
                kind: .live,
                title: value.title,
                imageURLString: value.imageURL?.absoluteString
            )
        case .movie(let value):
            return MediaReference(
                id: value.id,
                sourceID: value.sourceID,
                kind: .movie,
                title: value.title,
                imageURLString: value.imageURL?.absoluteString
            )
        case .series(let value):
            return MediaReference(
                id: value.id,
                sourceID: value.sourceID,
                kind: .series,
                title: value.title,
                imageURLString: value.imageURL?.absoluteString
            )
        case .episode:
            return nil
        }
    }
}

/// Tek bir öğenin oynatılabilir hâli.
///
/// `MediaItem` protokolünü doğrudan kullanmak yerine somut bir yapı tercih
/// edildi: oynatıcı, favoriler ve "son izlenenler" bu yapıyı saklar ve
/// kimliği (kaynak + tür + id) kaybetmez.
struct AnyMediaItem: MediaItem {

    let id: String
    let title: String
    let imageURL: URL?
    let streamURL: URL
    let sourceID: UUID
    let kind: CategoryKind

    /// İkincil başlık: kategori adı veya dizi adı.
    let contextTitle: String?
    /// Açıklama: film özeti veya bölüm özeti.
    let detail: String?

    init(
        id: String,
        title: String,
        imageURL: URL?,
        streamURL: URL,
        sourceID: UUID,
        kind: CategoryKind,
        contextTitle: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.imageURL = imageURL
        self.streamURL = streamURL
        self.sourceID = sourceID
        self.kind = kind
        self.contextTitle = contextTitle
        self.detail = detail
    }

    /// Bölümler için dizi bağlamını kurar.
    static func episode(_ episode: Episode, seriesTitle: String?) -> AnyMediaItem {
        AnyMediaItem(
            id: episode.id,
            title: episode.fullTitle,
            imageURL: episode.imageURL,
            streamURL: episode.streamURL,
            sourceID: episode.sourceID,
            kind: .series,
            contextTitle: seriesTitle,
            detail: episode.plot
        )
    }
}
