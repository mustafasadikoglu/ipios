import Foundation

/// Dizi (üst düzey kayıt). Bölümler `SeriesDetail` içinde gelir.
struct Series: Identifiable, Hashable, Codable {
    let id: String
    let sourceID: UUID
    let title: String
    let imageURL: URL?

    let categoryID: String?
    let categoryName: String?

    let plot: String?
    let year: String?
    let rating: String?
    let genre: String?

    /// Son bölüm eklendiği tarih (varsa).
    let lastModified: Date?

    let order: Int

    init(
        id: String,
        sourceID: UUID,
        title: String,
        imageURL: URL?,
        categoryID: String? = nil,
        categoryName: String? = nil,
        plot: String? = nil,
        year: String? = nil,
        rating: String? = nil,
        genre: String? = nil,
        lastModified: Date? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.imageURL = imageURL
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.plot = plot
        self.year = year
        self.rating = rating
        self.genre = genre
        self.lastModified = lastModified
        self.order = order
    }
}

/// Dizi detayı: sezonlar ve bölümler.
struct SeriesDetail: Identifiable, Hashable {
    let series: Series
    let seasons: [Season]

    var id: String { series.id }

    var episodeCount: Int {
        seasons.reduce(0) { $0 + $1.episodes.count }
    }
}

/// Bir sezon.
struct Season: Identifiable, Hashable {
    let number: Int
    var episodes: [Episode]

    var id: Int { number }

    var displayName: String { L.f("season.name", number) }
}

/// Tek bir bölüm. Doğrudan oynatılabilir olduğu için `MediaItem`'a uyar.
struct Episode: MediaItem, Hashable {
    let id: String
    let sourceID: UUID
    let seriesID: String
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let imageURL: URL?
    let streamURL: URL
    let plot: String?
    let durationSeconds: Double?

    var kind: CategoryKind { .series }

    /// `1x03`
    var displayName: String {
        L.f("episode.number", seasonNumber, episodeNumber)
    }

    var fullTitle: String {
        title.isEmpty ? L.f("episode.untitled", displayName) : L.f("episode.fullTitle", displayName, title)
    }

    var durationText: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        return Format.duration(durationSeconds)
    }
}
