import Foundation

/// Kullanıcının eklediği IPTV kaynağı.
///
/// Şifre bu modelde **düz metin tutulmaz**. Yalnızca `credentialKey` alanı
/// bulunur; gerçek şifre Keychain'de bu anahtarın altında saklanır.
struct PlaylistSource: Identifiable, Codable, Hashable {

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case xtream
        case m3u

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .xtream: return L.t("source.kind.xtream")
            case .m3u: return L.t("source.kind.m3u")
            }
        }

        var iconName: String {
            switch self {
            case .xtream: return "server.rack"
            case .m3u: return "list.bullet.rectangle"
            }
        }
    }

    var id: UUID
    var name: String
    var kind: Kind

    /// Xtream için `http://sunucu:port`, M3U için playlist URL'si.
    var baseURL: URL

    /// Yalnızca Xtream kaynaklarında dolu.
    var username: String?

    /// Şifrenin Keychain'deki anahtarı. Örn: `source.<uuid>.password`
    var credentialKey: String?

    /// Opsiyonel XMLTV / EPG kaynağı.
    var epgURL: URL?

    /// Son başarılı senkronizasyon zamanı.
    var lastSyncedAt: Date?

    /// Bağlantı testinde alınan kısa durum bilgisi (kullanıcıya gösterilir).
    var statusNote: String?

    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        baseURL: URL,
        username: String? = nil,
        credentialKey: String? = nil,
        epgURL: URL? = nil,
        lastSyncedAt: Date? = nil,
        statusNote: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.username = username
        self.credentialKey = credentialKey
        self.epgURL = epgURL
        self.lastSyncedAt = lastSyncedAt
        self.statusNote = statusNote
        self.isEnabled = isEnabled
    }

    /// Keychain anahtarını üretir ve modele yazar.
    mutating func assignCredential(_ password: String) throws {
        let key = Self.credentialKey(for: id)
        try KeychainStore.save(password, for: key)
        self.credentialKey = key
    }

    var password: String? {
        guard let credentialKey else { return nil }
        return KeychainStore.read(credentialKey)
    }

    var hasPassword: Bool {
        guard let credentialKey else { return false }
        return KeychainStore.exists(credentialKey)
    }

    func removeCredential() {
        guard let credentialKey else { return }
        try? KeychainStore.delete(credentialKey)
    }

    static func credentialKey(for id: UUID) -> String {
        "source.\(id.uuidString).password"
    }

    /// Kullanıcıya gösterilecek güvenli özet (şifre içermez).
    var displayHost: String {
        baseURL.host ?? baseURL.absoluteString
    }
}

extension PlaylistSource {
    /// Geliştirme sırasında kullanılan örnek kaynak.
    static let preview = PlaylistSource(
        name: "Örnek Sağlayıcı",
        kind: .xtream,
        baseURL: URL(string: "http://example.com:8080")!,
        username: "demo"
    )
}
