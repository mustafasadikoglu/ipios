import SwiftUI

/// Dizi detayı: sezon seçici ve bölüm listesi.
///
/// Bölümler liste yüklemesinde gelmediği için (Xtream'de dizi başına ayrı bir
/// istek gerekir) bu ekran açıldığında kısa bir yükleme durumu gösterilir.
/// Dizi kaydının kendisi oynatılamaz; oynatma yalnızca bir bölüme dokununca
/// başlar.
struct SeriesDetailView: View {

    @ObservedObject private var environment: AppEnvironment
    @StateObject private var viewModel: SeriesDetailViewModel

    init(series: Series, environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(
            wrappedValue: SeriesDetailViewModel(series: series, environment: environment)
        )
    }

    var body: some View {
        content
            .screenBackground()
            .navigationTitle(viewModel.series.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FavoriteStarButton(
                        isFavorite: viewModel.isFavorite,
                        action: { viewModel.toggleFavorite() }
                    )
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
    }

    // MARK: - İçerik

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.seasons.isEmpty {
            LoadingView()
        } else if let message = viewModel.errorMessage, viewModel.seasons.isEmpty {
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        } else if viewModel.seasons.isEmpty {
            EmptyStateView(
                icon: "rectangle.stack",
                title: L.t("series.detail.empty.title"),
                message: L.t("series.detail.empty.message")
            )
        } else {
            scroll
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.gutter) {
                header

                if viewModel.seasons.count > 1 {
                    seasonPicker
                }

                episodeList
            }
            .padding(.vertical, Theme.Metrics.gutter)
        }
    }

    // MARK: - Başlık

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Metrics.rowSpacing) {
            RemoteImage.poster(viewModel.series.imageURL, title: viewModel.series.title, width: 96)

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.episodeCountText)
                    .font(Theme.Fonts.rowSubtitle)
                    .foregroundStyle(Theme.textSecondary)

                if let meta = metaText {
                    Text(meta)
                        .font(Theme.Fonts.numeric)
                        .foregroundStyle(Theme.textTertiary)
                }

                if let plot = viewModel.series.plot, !plot.isEmpty {
                    Text(plot)
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
    }

    /// "2023 • Dram • 16+" biçiminde ikincil bilgi satırı.
    private var metaText: String? {
        var parts: [String] = []
        if let year = viewModel.series.year, !year.isEmpty { parts.append(year) }
        if let genre = viewModel.series.genre, !genre.isEmpty { parts.append(genre) }
        if let rating = viewModel.series.rating, !rating.isEmpty { parts.append(rating) }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    // MARK: - Sezonlar

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.seasons) { season in
                    let isSelected = season.number == viewModel.selectedSeason?.number
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            viewModel.selectedSeasonNumber = season.number
                        }
                    } label: {
                        Text(season.displayName)
                            .font(Theme.Fonts.rowSubtitle.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isSelected ? Theme.accent : Theme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
        }
    }

    // MARK: - Bölümler

    private var episodeList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: L.t("series.episodes"),
                subtitle: L.f("series.episodeCount", viewModel.episodes.count)
            )
            .padding(.bottom, 8)

            ForEach(viewModel.episodes) { episode in
                episodeRow(episode)

                Divider()
                    .overlay(Theme.separator)
                    .padding(.leading, Theme.Metrics.gutter + 46 + Theme.Metrics.rowSpacing)
            }
        }
    }

    private func episodeRow(_ episode: Episode) -> some View {
        MediaRow(
            title: episode.displayName,
            subtitle: episode.title.isEmpty ? episode.plot : episode.title,
            imageURL: episode.imageURL ?? viewModel.series.imageURL,
            progress: viewModel.position(for: episode)?.progress ?? 0,
            trailingText: episode.durationText,
            actions: MediaRowActions(
                showsFavoriteButton: false,
                onSelect: { presenter.present(.episode(episode)) }
            )
        )
    }

    @EnvironmentObject private var presenter: PlayerPresenter
}
