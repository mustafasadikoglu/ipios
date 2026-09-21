import Foundation

/// Elektronik yayın rehberindeki tek bir program.
struct EPGProgram: Identifiable, Hashable, Codable {
    let id: String
    /// Programın ait olduğu kanalın EPG kimliği (`tvg-id` / `epg_channel_id`).
    let channelID: String
    let title: String
    let subtitle: String?
    let description: String?
    let start: Date
    let end: Date
    let category: String?

    init(
        id: String = UUID().uuidString,
        channelID: String,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        start: Date,
        end: Date,
        category: String? = nil
    ) {
        self.id = id
        self.channelID = channelID
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.start = start
        self.end = end
        self.category = category
    }

    var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    /// Program şu an yayında mı?
    var isLive: Bool {
        let now = Date()
        return now >= start && now < end
    }

    /// Geçmiş mi?
    var isPast: Bool {
        Date() >= end
    }

    /// `0...1` arası ilerleme; yayında değilse 0.
    var progress: Double {
        guard isLive, duration > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(max(elapsed / duration, 0), 1)
    }

    /// Kalan süre (saniye); program bittiyse 0.
    var remaining: TimeInterval {
        max(0, end.timeIntervalSinceNow)
    }

    /// Başlangıç-bitiş saat aralığı.
    var timeRangeText: String {
        Format.timeRange(from: start, to: end)
    }
}
