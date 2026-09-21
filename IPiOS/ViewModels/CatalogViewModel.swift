import Foundation
import SwiftUI

/// Canlı / film / dizi listelerinin ortak davranışı.
///
/// Üç sekme de aynı işi yapar: bir kaynaktan listeyi al, kategoriye ve arama
/// metnine göre süz, hata ve yükleniyor durumunu yönet. Bu davranışı üç kez
/// yazmak yerine tek yerde topluyoruz; alt sınıflar yalnızca kendine özgü
/// kısmı (örneğin canlı yayında EPG) ekler.
@MainActor
class CatalogViewModel: ObservableObject {

    let kind: CategoryKind

    @Published var selectedCategoryID: String?
    @Published var searchText: String = ""

    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    /// Yalnızca favorileri göster.
    @Published var showsFavoritesOnly = false

    let environment: AppEnvironment
    private let debouncer = Debouncer()
    private var loadTask: Task<Void, Never>?

    init(kind: CategoryKind, environment: AppEnvironment) {
        self.kind = kind
        self.environment = environment
    }

    // MARK: - Kaynak veriler

    var library: ContentLibrary { environment.library }

    var categories: [Category] {
        [Category.all(kind: kind)] + library.categories(for: kind)
    }

    var allItems: [PlayableItem] {
        library.items(kind)
    }

    /// Kategori, arama metni ve favori filtresi uygulanmış liste.
    var visibleItems: [PlayableItem] {
        var result = allItems

        if let selectedCategoryID, selectedCategoryID != Category.allID {
            result = result.filter { item in
                switch item {
                case .channel(let value):
                    return matches(value.categoryID, value.categoryName, selectedCategoryID)
                case .movie(let value):
                    return matches(value.categoryID, value.categoryName, selectedCategoryID)
                case .series(let value):
                    return matches(value.categoryID, value.categoryName, selectedCategoryID)
                case .episode(let value):
                    // Dizi listesinde kategori, dizinin kendi kategorisidir;
                    // bölümler yalnızca detay ekranında görünür.
                    return false
                }
            }
        }

        if showsFavoritesOnly {
            result = result.filter { item in
                guard let reference = item.reference else { return false }
                return environment.favorites.isFavorite(reference)
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.searchText.localizedCaseInsensitiveContains(query) }
        }

        return result
    }

    var resultCount: Int { visibleItems.count }

    /// Hiç veri yokken mi boş, yoksa filtre mi sonuç vermedi?
    var isFiltered: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (selectedCategoryID != nil && selectedCategoryID != Category.allID)
            || showsFavoritesOnly
    }

    private func matches(_ id: String?, _ name: String?, _ selected: String) -> Bool {
        id == selected || name == selected
    }

    // MARK: - Yükleme

    /// Ekran göründüğünde bir kez yükler; liste zaten bellekteyse dokunmaz.
    func loadIfNeeded() async {
        guard !library.hasLoaded(kind) else { return }
        await load(force: false)
    }

    func reload() async {
        await load(force: true)
    }

    func load(force: Bool) async {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.environment.loadLibrary([self.kind], force: force)
                guard !Task.isCancelled else { return }
                self.isLoading = false
                await self.didLoad()
            } catch is CancellationError {
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.errorMessage = Self.message(for: error)
            }
        }
        loadTask = task
        await task.value
    }

    /// Alt sınıfların yükleme sonrası ek iş yapması için (EPG gibi).
    func didLoad() async {}

    func clearFilters() {
        selectedCategoryID = nil
        searchText = ""
        showsFavoritesOnly = false
    }

    /// Arama metnini geciktirerek uygular.
    ///
    /// 100 bin satırlık listelerde her tuş vuruşunda filtrelemek kaydırmayı
    /// takar; bu yüzden kısa bir bekleme sonrası tek seferde süzülür.
    func searchTextDidChange() {
        debouncer.schedule { [weak self] in
            guard let self else { return }
            // SwiftUI, `searchText` zaten bir `@Published`; burada yalnızca
            // görünümün yeniden çizilmesini tetiklemek yeterli.
            self.objectWillChange.send()
        }
    }

    static func message(for error: Error) -> String {
        if let appError = error as? AppError {
            return appError.errorDescription ?? L.t("error.unknown")
        }
        return error.localizedDescription
    }
}
