import Foundation
import SwiftUI

/// Filmler sekmesi.
@MainActor
final class MoviesViewModel: CatalogViewModel {

    /// Ekranın üstünde "İzlemeye Devam Et" şeridi gösterilsin mi?
    var resumeItems: [PlayableItem] {
        environment.recents.resumeList.compactMap { entry in
            guard entry.reference.kind == .movie else { return nil }
            return library.resolve(entry.reference)
        }
    }

    var favoriteMovies: [PlayableItem] {
        guard library.hasLoaded(.movie) else { return [] }
        return environment.favorites.movieFavorites.compactMap { library.resolve($0) }
    }

    func position(for item: PlayableItem) -> RecentsRepository.Position? {
        guard let playable = item.playable else { return nil }
        return environment.recents.position(for: playable)
    }
}
