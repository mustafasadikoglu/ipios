import Foundation
import SwiftUI

/// Favoriler: kayıtlı referansları bellekteki listeye çözer.
///
/// Favori kaydı yalnızca kimlik ve başlık taşır (şifre ya da yayın adresi
/// taşımaz). Göstermek için güncel listeye ihtiyaç vardır; liste henüz
/// yüklenmediyse ekran kullanıcıya bunu söyler.
@MainActor
final class FavoritesViewModel: ObservableObject {

    enum Kind: String, CaseIterable, Identifiable {
        case live
        case movie
        case series

        var id: String { rawValue }

        var categoryKind: CategoryKind {
            switch self {
            case .live: return .live
            case .movie: return .movie
            case .series: return .series
            }
        }

        var title: String { categoryKind.displayName }
    }

    @Published var selectedKind: Kind = .live
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var references: [MediaReference] {
        environment.favorites.favorites(of: selectedKind.categoryKind)
    }

    /// Bellekteki listeye çözülebilen favoriler.
    func items(for kind: Kind) -> [PlayableItem] {
        environment.favorites
            .favorites(of: kind.categoryKind)
            .compactMap { environment.library.resolve($0) }
    }

    var selectedItems: [PlayableItem] { items(for: selectedKind) }

    var isEmpty: Bool { references.isEmpty }

    /// Favori var ama liste yüklü olmadığı için gösterilemiyor mu?
    var isWaitingForLibrary: Bool {
        !isEmpty && !environment.library.hasLoaded(selectedKind.categoryKind)
    }

    func loadIfNeeded() async {
        guard !environment.library.hasLoaded(selectedKind.categoryKind) else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await environment.loadLibrary([selectedKind.categoryKind])
        } catch is CancellationError {
            // yoksay
        } catch {
            errorMessage = CatalogViewModel.message(for: error)
        }
        isLoading = false
    }

    func isFavorite(_ item: PlayableItem) -> Bool {
        guard let reference = item.reference else { return false }
        return environment.favorites.isFavorite(reference)
    }

    func remove(_ item: PlayableItem) {
        guard let reference = item.reference else { return }
        let favorites = environment.favorites
        Task { await favorites.remove(reference) }
    }

    func removeAll() {
        let favorites = environment.favorites
        Task { await favorites.removeAll() }
    }
}
