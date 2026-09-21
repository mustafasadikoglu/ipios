import Foundation

/// Canlı TV kanalı.
struct Channel: MediaItem, Codable {
    let id: String
    let sourceID: UUID
    let title: String
    let imageURL: URL?
    let streamURL: URL

    let categoryID: String?
    let categoryName: String?

    /// Xtream `tv_archive` alanı; catch-up desteği için (v1.1).
    let hasArchive: Bool

    /// EPG eşleştirmesi için kullanılan `tvg-id`. Xtream'de `epg_channel_id`.
    let epgChannelID: String?

    let order: Int

    var kind: CategoryKind { .live }

    init(
        id: String,
        sourceID: UUID,
        title: String,
        imageURL: URL?,
        streamURL: URL,
        categoryID: String? = nil,
        categoryName: String? = nil,
        hasArchive: Bool = false,
        epgChannelID: String? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.imageURL = imageURL
        self.streamURL = streamURL
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.hasArchive = hasArchive
        self.epgChannelID = epgChannelID
        self.order = order
    }
}
