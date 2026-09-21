import Foundation

/// İsteğe bağlı izleme (VOD) filmi.
struct Movie: MediaItem, Codable {
    let id: String
    let sourceID: UUID
    let title: String
    let imageURL: URL?
    let streamURL: URL

    let categoryID: String?
    let categoryName: String?

    /// Konu özeti.
    let plot: String?
    /// Yapım yılı.
    let year: String?
    /// Süre, saniye.
    let durationSeconds: Double?
    /// Yaş sınırı / derecelendirme.
    let rating: String?
    /// Tür: Aksiyon, Dram vb.
    let genre: String?

    /// Xtream `container_extension` (mp4, mkv, m3u8...).
    let containerExtension: String?

    let order: Int

    var kind: CategoryKind { .movie }

    /// `3 sa 12 dk` biçiminde okunabilir süre.
    var durationText: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let minutes = Int(durationSeconds / 60)
        let h = minutes / 60
        let m = minutes % 60
        return h > 0
            ? L.f("format.duration.hoursMinutes", h, m)
            : L.f("format.duration.minutes", m)
    }

    init(
        id: String,
        sourceID: UUID,
        title: String,
        imageURL: URL?,
        streamURL: URL,
        categoryID: String? = nil,
        categoryName: String? = nil,
        plot: String? = nil,
        year: String? = nil,
        durationSeconds: Double? = nil,
        rating: String? = nil,
        genre: String? = nil,
        containerExtension: String? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.imageURL = imageURL
        self.streamURL = streamURL
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.plot = plot
        self.year = year
        self.durationSeconds = durationSeconds
        self.rating = rating
        self.genre = genre
        self.containerExtension = containerExtension
        self.order = order
    }
}
