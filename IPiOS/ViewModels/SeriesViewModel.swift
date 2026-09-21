import Foundation
import SwiftUI

/// Diziler sekmesi. Bölümler liste ekranında gösterilmez; diziye dokunulunca
/// detay ekranı açılır.
@MainActor
final class SeriesViewModel: CatalogViewModel {

    var favoriteSeries: [PlayableItem] {
        guard library.hasLoaded(.series) else { return [] }
        return environment.favorites.seriesFavorites.compactMap { library.resolve($0) }
    }

    /// Henüz izlenmeye başlanmış diziler (ilk bölümü izlenmiş olanlar).
    var continueWatching: [PlayableItem] {
        let watchedSeriesIDs = Set(
            environment.recents.recents
                .filter { $0.kind == .series }
                .map(\.id)
        )
        guard !watchedSeriesIDs.isEmpty else { return [] }
        return library.seriesList
            .filter { watchedSeriesIDs.contains($0.id) }
            .map(PlayableItem.series)
    }
}
