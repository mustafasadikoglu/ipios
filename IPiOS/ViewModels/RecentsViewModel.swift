import Foundation
import SwiftUI

/// Son izlenenler ve "izlemeye devam et" listesi.
@MainActor
final class RecentsViewModel: ObservableObject {

    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    struct Entry: Identifiable {
        let reference: MediaReference
        let position: RecentsRepository.Position?
        let item: PlayableItem?

        var id: String { reference.stableKey }
        var progress: Double { position?.progress ?? 0 }
    }

    /// Devam edilebilecek içerikler (konumu olanlar), en yeni önce.
    var resumeEntries: [Entry] {
        environment.recents.resumeList.map { entry in
            Entry(
                reference: entry.reference,
                position: entry.position,
                item: environment.library.resolve(entry.reference)
            )
        }
    }

    /// Tüm son izlenenler.
    var allEntries: [Entry] {
        environment.recents.recents.map { reference in
            Entry(
                reference: reference,
                position: environment.recents.positions[reference.stableKey],
                item: environment.library.resolve(reference)
            )
        }
    }

    var isEmpty: Bool { environment.recents.recents.isEmpty }

    /// Liste yüklü değilse öğeler çözülemez; ekran bunu bildirmeli.
    var needsLibrary: Bool {
        !isEmpty && !allKindsLoaded
    }

    private var allKindsLoaded: Bool {
        CategoryKind.allCases.allSatisfy { environment.library.hasLoaded($0) }
    }

    func loadIfNeeded() async {
        guard !allKindsLoaded else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await environment.loadLibrary(CategoryKind.allCases)
        } catch is CancellationError {
            // yoksay
        } catch {
            errorMessage = CatalogViewModel.message(for: error)
        }
        isLoading = false
    }

    func clearHistory() async {
        await environment.recents.clearRecents()
    }

    func clearPositions() async {
        await environment.recents.clearAllPositions()
    }
}
