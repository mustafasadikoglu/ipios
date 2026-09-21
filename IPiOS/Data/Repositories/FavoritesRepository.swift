import Foundation

/// Favori kanal / film / dizi kayıtlarını tutar.
///
/// Kayıt olarak `MediaReference` saklanır: liste yeniden yüklendiğinde öğe
/// artık mevcut olmasa bile kayıt anlamlı kalır ve kullanıcıya gösterilebilir.
@MainActor
final class FavoritesRepository: ObservableObject {

    @Published private(set) var favorites: [MediaReference] = []

    private let store: JSONFileStore
    private let fileName = "favorites.json"
    private var index: Set<String> = []

    init(store: JSONFileStore = JSONFileStore()) {
        self.store = store
    }

    func load() async {
        do {
            favorites = try await store.load([MediaReference].self, from: fileName) ?? []
            rebuildIndex()
        } catch {
            Log.storage.error("Favoriler yuklenemedi: \(error.localizedDescription, privacy: .public)")
            favorites = []
            index = []
        }
    }

    // MARK: - Sorgular

    func isFavorite(_ item: any MediaItem) -> Bool {
        index.contains(item.stableKey)
    }

    func isFavorite(_ reference: MediaReference) -> Bool {
        index.contains(reference.stableKey)
    }

    func favorites(of kind: CategoryKind) -> [MediaReference] {
        favorites.filter { $0.kind == kind }
    }

    var liveFavorites: [MediaReference] { favorites(of: .live) }
    var movieFavorites: [MediaReference] { favorites(of: .movie) }
    var seriesFavorites: [MediaReference] { favorites(of: .series) }

    // MARK: - Değişiklikler

    func add(_ reference: MediaReference) async {
        guard !index.contains(reference.stableKey) else { return }
        favorites.insert(reference, at: 0)
        rebuildIndex()
        await persist()
    }

    func toggle(_ item: any MediaItem) async {
        await toggle(MediaReference(item: item))
    }

    /// Favori durumunu hazır bir kayıt üzerinden değiştirir.
    ///
    /// `MediaItem`'a uymayan kayıtlar (ör. dizi) için ayrı bir yol gerekir;
    /// mantık tek yerde kalsın diye `MediaItem` sürümü de buraya devreder.
    func toggle(_ reference: MediaReference) async {
        let key = reference.stableKey
        if index.contains(key) {
            favorites.removeAll { $0.stableKey == key }
        } else {
            favorites.insert(reference, at: 0)
        }
        rebuildIndex()
        await persist()
    }

    func remove(_ reference: MediaReference) async {
        favorites.removeAll { $0.stableKey == reference.stableKey }
        rebuildIndex()
        await persist()
    }

    func removeAll() async {
        favorites.removeAll()
        index.removeAll()
        await persist()
    }

    // MARK: - Private

    private func rebuildIndex() {
        index = Set(favorites.map(\.stableKey))
    }

    private func persist() async {
        do {
            try await store.save(favorites, as: fileName)
        } catch {
            Log.storage.error("Favoriler kaydedilemedi: \(error.localizedDescription, privacy: .public)")
        }
    }
}
