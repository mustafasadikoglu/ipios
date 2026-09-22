import Foundation

/// Kaynak listesini yönetir ve her kaynak için uygun `PlaylistProviding`
/// implementasyonunu üretir.
///
/// UI katmanı yalnızca bu sınıfla konuşur; Xtream ve M3U ayrımı burada kapanır.
@MainActor
final class SourcesRepository: ObservableObject {

    /// Kayıtlı tüm kaynaklar.
    @Published private(set) var sources: [PlaylistSource] = []

    /// Şu an aktif olan kaynak.
    @Published var activeSourceID: UUID?

    private let store: JSONFileStore
    private let network: NetworkClient
    private let fileName = "sources.json"
    private let activeKey = "activeSourceID"

    init(network: NetworkClient = NetworkClient(), store: JSONFileStore = JSONFileStore()) {
        self.network = network
        self.store = store
    }

    // MARK: - Yükleme / kaydetme

    /// Kayıtlı kaynakları okur.
    ///
    /// Neden `throws`: hata burada yutulursa bozuk bir kaynak dosyası "hiç
    /// kaynak eklenmemiş" gibi görünür ve kullanıcı verisinin kaybolduğunu
    /// anlamaz. Hata çağırana (açılış akışına) taşınır; orada kullanıcıya
    /// anlaşılır bir mesaj ve yeniden deneme yolu sunulur.
    func load() async throws {
        let loaded = try await store.load([PlaylistSource].self, from: fileName) ?? []
        sources = loaded

        if let stored = UserDefaults.standard.string(forKey: activeKey),
           let id = UUID(uuidString: stored),
           loaded.contains(where: { $0.id == id }) {
            activeSourceID = id
        } else {
            activeSourceID = loaded.first(where: \.isEnabled)?.id
        }
    }

    private func persist() async {
        do {
            try await store.save(sources, as: fileName)
        } catch {
            Log.storage.error("Kaynaklar kaydedilemedi: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sorgular

    var activeSource: PlaylistSource? {
        guard let activeSourceID else { return sources.first(where: \.isEnabled) }
        return sources.first { $0.id == activeSourceID }
    }

    func source(with id: UUID) -> PlaylistSource? {
        sources.first { $0.id == id }
    }

    var enabledSources: [PlaylistSource] {
        sources.filter(\.isEnabled)
    }

    // MARK: - Değişiklikler

    func add(_ source: PlaylistSource, password: String?) async throws {
        var newSource = source
        if let password, !password.isEmpty {
            try newSource.assignCredential(password)
        }
        sources.append(newSource)
        await persist()
        if activeSourceID == nil {
            await setActive(newSource.id)
        }
    }

    func update(_ source: PlaylistSource) async {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
        await persist()
    }

    func updatePassword(for id: UUID, password: String) async throws {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        try sources[index].assignCredential(password)
        await persist()
    }

    func remove(_ id: UUID) async {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].removeCredential()
        sources.remove(at: index)

        if activeSourceID == id {
            activeSourceID = sources.first(where: \.isEnabled)?.id
            persistActive()
        }
        await persist()
    }

    func setActive(_ id: UUID) async {
        activeSourceID = id
        persistActive()
    }

    func markSynced(_ id: UUID, note: String? = nil) async {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].lastSyncedAt = Date()
        sources[index].statusNote = note
        await persist()
    }

    private func persistActive() {
        UserDefaults.standard.set(activeSourceID?.uuidString, forKey: activeKey)
    }

    // MARK: - Sağlayıcı üretimi

    /// Bir kaynak için playlist sağlayıcısı üretir.
    ///
    /// - Parameter localFileURL: M3U kaynağı dosyadan içe aktarıldıysa.
    ///   Verilmezse kaynağın `baseURL`'ü dosya adresi ise otomatik kullanılır.
    func provider(for source: PlaylistSource, localFileURL: URL? = nil) throws -> PlaylistProviding {
        switch source.kind {
        case .xtream:
            guard let username = source.username, !username.isEmpty else {
                throw AppError.badCredentials
            }
            guard let password = source.password, !password.isEmpty else {
                throw AppError.badCredentials
            }
            return XtreamClient(source: source, password: password, network: network)

        case .m3u:
            // Dosyadan içe aktarılan playlistlerde `baseURL` bir dosya yoludur.
            let fileURL = localFileURL ?? (source.baseURL.isFileURL ? source.baseURL : nil)
            return M3UPlaylistProvider(source: source, localFileURL: fileURL, network: network)
        }
    }

    /// Aktif kaynak için sağlayıcı üretir.
    func activeProvider() throws -> PlaylistProviding? {
        guard let source = activeSource else { return nil }
        return try provider(for: source)
    }

    /// Aktif kaynak için EPG servisi üretir.
    ///
    /// Xtream kaynaklarında EPG adresi `xmltv.php` yolundan otomatik türetilir;
    /// kullanıcı ayrıca kendi XMLTV adresini girebilir.
    func epgProvider(for source: PlaylistSource) -> EPGProviding {
        if let epgURL = source.epgURL {
            return EPGService(sourceID: source.id, remoteURL: epgURL, network: network)
        }

        if source.kind == .xtream,
           let password = source.password,
           let username = source.username,
           let xmltvURL = xtreamXMLTVURL(source: source, username: username, password: password) {
            return EPGService(sourceID: source.id, remoteURL: xmltvURL, network: network)
        }

        return EmptyEPGProvider()
    }

    private func xtreamXMLTVURL(source: PlaylistSource, username: String, password: String) -> URL? {
        var components = URLComponents(url: source.baseURL, resolvingAgainstBaseURL: false)
        // Kullanıcının adreste verdiği yol öneki korunur: sağlayıcısını bir alt
        // yol altında sunan panellerde (`http://host/iptv`) öneki atmak isteği
        // yanlış adrese gönderir ve EPG sessizce boş kalırdı.
        var prefix = source.baseURL.path
        while prefix.hasSuffix("/") { prefix.removeLast() }
        components?.path = prefix + "/xmltv.php"
        components?.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        return components?.url
    }
}
