import Foundation

/// Yüklenen içerik listelerinin ortak belleği.
///
/// Neden gerekli: aynı kanal / film / dizi listesi birden fazla ekranda
/// gerekiyor — sekmeler, arama ve favoriler. Her ekranın listeyi bağımsız
/// indirmesi hem yavaş hem de tutarsız olurdu (bir ekranda görünen kanal
/// diğerinde olmayabilirdi). Bu yüzden liste bir kez çekilir ve burada tutulur.
///
/// Bellek uygulama ömrüyle sınırlıdır; diske yazılmaz. Kaynak değiştiğinde
/// `prepare(for:)` çağrısı belleği temizler.
@MainActor
final class ContentLibrary: ObservableObject {

    /// Listenin hangi kaynağa ait olduğu.
    @Published private(set) var sourceID: UUID?

    @Published private(set) var channels: [Channel] = []
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var seriesList: [Series] = []

    /// Kategori listeleri türe göre.
    @Published private(set) var categoryIndex: [CategoryKind: [Category]] = [:]

    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isLoading = false

    /// Hangi türlerin indirildiği. "Boş liste" ile "henüz indirilmedi"
    /// ayrımını yapabilmek için ayrı tutulur.
    private var loadedKinds: Set<CategoryKind> = []

    // MARK: - Sorgular

    func hasLoaded(_ kind: CategoryKind) -> Bool {
        loadedKinds.contains(kind)
    }

    var isCompletelyEmpty: Bool {
        loadedKinds.isEmpty
    }

    func categories(for kind: CategoryKind) -> [Category] {
        categoryIndex[kind] ?? []
    }

    /// Bir türdeki tüm öğeler, `PlayableItem` olarak.
    func items(_ kind: CategoryKind) -> [PlayableItem] {
        switch kind {
        case .live: return channels.map(PlayableItem.channel)
        case .movie: return movies.map(PlayableItem.movie)
        case .series: return seriesList.map(PlayableItem.series)
        }
    }

    /// Kayıtlı bir referansı (favori veya son izlenen) oynatılabilir öğeye
    /// çevirir. Liste yüklü değilse ya da öğe artık mevcut değilse `nil`.
    func resolve(_ reference: MediaReference) -> PlayableItem? {
        switch reference.kind {
        case .live:
            return channels.first { $0.id == reference.id }.map(PlayableItem.channel)
        case .movie:
            return movies.first { $0.id == reference.id }.map(PlayableItem.movie)
        case .series:
            return seriesList.first { $0.id == reference.id }.map(PlayableItem.series)
        }
    }

    func channel(withID id: String) -> Channel? {
        channels.first { $0.id == id }
    }

    // MARK: - Yükleme

    /// Aktif kaynak değiştiyse belleği boşaltır.
    func prepare(for newSourceID: UUID?) {
        guard sourceID != newSourceID else { return }
        reset()
        sourceID = newSourceID
    }

    /// Verilen türler için liste henüz yoksa indirir; olanları atlar.
    ///
    /// - Parameter force: `true` ise mevcut listeler de yeniden indirilir
    ///   (kullanıcı "yenile" dediğinde).
    func ensureLoaded(
        _ kinds: [CategoryKind],
        using provider: PlaylistProviding,
        force: Bool = false
    ) async throws {
        let pending = kinds.filter { force || !hasLoaded($0) }
        guard !pending.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        for kind in pending {
            try Task.checkCancellation()

            categoryIndex[kind] = try await provider.categories(kind: kind)

            switch kind {
            case .live:
                channels = try await provider.channels(categoryID: nil)
            case .movie:
                movies = try await provider.movies(categoryID: nil)
            case .series:
                seriesList = try await provider.seriesList(categoryID: nil)
            }

            loadedKinds.insert(kind)
        }

        lastUpdatedAt = Date()
    }

    func reset() {
        channels = []
        movies = []
        seriesList = []
        categoryIndex = [:]
        loadedKinds = []
        lastUpdatedAt = nil
    }
}
