import Foundation

/// Tüm playlist kaynaklarının ortak arayüzü.
///
/// İki somut implementasyon vardır: `XtreamClient` ve `M3UPlaylistProvider`.
/// UI katmanı kaynağın hangi tip olduğunu bilmez; yalnızca bu protokolü görür.
protocol PlaylistProviding: Sendable {

    /// Kaynağın kimliği.
    var sourceID: UUID { get }

    /// Kaynağın bağlantı ve kimlik bilgilerini doğrular.
    func validate() async throws -> SourceInfo

    /// Belirtilen türdeki kategorileri getirir.
    func categories(kind: CategoryKind) async throws -> [Category]

    /// Canlı kanalları getirir. `categoryID` nil ise tümü döner.
    func channels(categoryID: String?) async throws -> [Channel]

    /// Filmleri getirir.
    func movies(categoryID: String?) async throws -> [Movie]

    /// Dizileri getirir.
    func seriesList(categoryID: String?) async throws -> [Series]

    /// Bir dizinin sezon/bölüm yapısını getirir.
    func seriesDetail(seriesID: String) async throws -> SeriesDetail
}

/// `validate()` çağrısının döndürdüğü kaynak bilgisi.
struct SourceInfo: Hashable, Sendable {
    /// Sağlayıcı durumu: "Active", "Expired", "Disabled"...
    let status: String?
    /// Abonelik bitiş tarihi.
    let expiresAt: Date?
    /// Aynı anda izlenebilecek bağlantı sayısı.
    let maxConnections: Int?
    /// Hesap oluşturma tarihi.
    let createdAt: Date?
    /// Canlı kanal sayısı (sağlayıcı bildiriyorsa).
    let liveCount: Int?
    /// Film sayısı.
    let movieCount: Int?
    /// Dizi sayısı.
    let seriesCount: Int?

    var isValid: Bool {
        guard let status else { return true }
        let normalized = status.lowercased()
        return normalized == "active" || normalized == "1" || normalized == "true"
    }

    var expiryText: String? {
        guard let expiresAt else { return nil }
        return Format.dateTimeFormatter.string(from: expiresAt)
    }

    static let unknown = SourceInfo(
        status: nil, expiresAt: nil, maxConnections: nil,
        createdAt: nil, liveCount: nil, movieCount: nil, seriesCount: nil
    )
}
