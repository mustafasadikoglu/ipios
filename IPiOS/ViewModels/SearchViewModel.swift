import Foundation
import SwiftUI
import Combine

/// Arama sekmesi: üç içerik türünde birden arar.
///
/// Arama tamamen yereldir; sunucuya istek gitmez. Nedeni: kanal listeleri
/// 100 bin satıra kadar çıkabiliyor ve Xtream API'de genel bir arama ucu
/// bulunmuyor. Liste bir kez indirilir, arama bellekte yapılır.
@MainActor
final class SearchViewModel: ObservableObject {

    @Published var query = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let environment: AppEnvironment
    private let debouncer = Debouncer()
    private var loadTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasQuery: Bool { normalizedQuery.count >= 2 }

    // MARK: - Sonuçlar

    var liveResults: [PlayableItem] { search(in: .live) }
    var movieResults: [PlayableItem] { search(in: .movie) }
    var seriesResults: [PlayableItem] { search(in: .series) }

    var totalCount: Int {
        liveResults.count + movieResults.count + seriesResults.count
    }

    var isEmpty: Bool {
        hasQuery && !isLoading && totalCount == 0 && errorMessage == nil
    }

    private func search(in kind: CategoryKind) -> [PlayableItem] {
        guard hasQuery else { return [] }

        // Sonuç listesini şişirmemek için tür başına bir üst sınır var;
        // kullanıcı zaten ilk sonuçlarla ilgilenir.
        let query = normalizedQuery
        return environment.library.items(kind)
            .lazy
            .filter { $0.searchText.localizedCaseInsensitiveContains(query) }
            .prefix(Self.perKindLimit)
            .map { $0 }
    }

    private static let perKindLimit = 60

    // MARK: - Yükleme

    /// Arama yapılabilmesi için üç listenin de bellekte olması gerekir.
    func prepare() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.environment.loadLibrary([.live, .movie, .series])
                self.isLoading = false
            } catch is CancellationError {
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.errorMessage = CatalogViewModel.message(for: error)
            }
        }
        loadTask = task
        await task.value
    }

    func retry() async {
        isLoading = false
        await prepare()
    }

    /// Yazma durduktan sonra sonuçları tazelemek için.
    func queryDidChange() {
        debouncer.schedule { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func clear() {
        query = ""
    }
}
