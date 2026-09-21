import Foundation
import SwiftUI

/// Dizi detayı: sezon ve bölüm listesi.
///
/// Bölümler liste yüklemesinde gelmez; Xtream'de dizi başına ayrı bir istek
/// gerekir (`get_series_info`). Bu yüzden detay yalnızca ekran açıldığında
/// yüklenir ve ardından bellekte tutulur.
@MainActor
final class SeriesDetailViewModel: ObservableObject {

    let series: Series

    @Published private(set) var seasons: [Season] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    /// Seçili sezon numarası.
    @Published var selectedSeasonNumber: Int?

    private let environment: AppEnvironment

    init(series: Series, environment: AppEnvironment) {
        self.series = series
        self.environment = environment
    }

    var selectedSeason: Season? {
        guard let selectedSeasonNumber else { return seasons.first }
        return seasons.first { $0.number == selectedSeasonNumber } ?? seasons.first
    }

    var episodes: [Episode] {
        selectedSeason?.episodes ?? []
    }

    var episodeCountText: String {
        L.f("series.episodeCount", seasons.reduce(0) { $0 + $1.episodes.count })
    }

    var isFavorite: Bool {
        environment.favorites.isFavorite(series)
    }

    func toggleFavorite() {
        let series = self.series
        let favorites = environment.favorites
        Task { await favorites.toggle(series) }
    }

    // MARK: - Yükleme

    func loadIfNeeded() async {
        guard seasons.isEmpty else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let provider = try environment.sources.activeProvider() else {
                throw AppError.sourceUnreachable
            }

            let detail = try await provider.seriesDetail(seriesID: series.id)
            seasons = detail.seasons
            if selectedSeasonNumber == nil {
                selectedSeasonNumber = seasons.first?.number
            }
        } catch is CancellationError {
            // Ekran kapandıysa hata göstermeye gerek yok.
        } catch {
            errorMessage = CatalogViewModel.message(for: error)
        }

        isLoading = false
    }

    // MARK: - Oynatma yardımcıları

    /// Bir bölümün kaldığı yer (varsa).
    func position(for episode: Episode) -> RecentsRepository.Position? {
        environment.recents.position(for: episode)
    }

    /// Sıradaki bölüm: aynı sezonun bir sonraki bölümü, yoksa sonraki sezonun
    /// ilk bölümü.
    func nextEpisode(after episode: Episode) -> Episode? {
        let flat = seasons.sorted { $0.number < $1.number }
            .flatMap { $0.episodes.sorted { $0.episodeNumber < $1.episodeNumber } }
        guard let index = flat.firstIndex(where: { $0.id == episode.id }),
              flat.indices.contains(index + 1) else { return nil }
        return flat[index + 1]
    }
}
