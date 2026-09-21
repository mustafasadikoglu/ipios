import SwiftUI

/// Arama sekmesi: canlı, film ve dizilerde tek aramada sonuç gösterir.
///
/// Arama sunucuda değil bellekte yapılır (bkz. `SearchViewModel`). Bu yüzden
/// sonuçlar üç bölüm hâlinde listelenir ve her bölüm yalnızca doluysa çizilir.
///
/// Aramaya başlamadan önce üç listenin de indirilmiş olması gerekir; bu
/// yüzden sekme açılır açılmaz `prepare()` çağrılır ve yükleme göstergesi
/// yalnızca henüz liste yokken görünür.
struct SearchView: View {

    @EnvironmentObject private var presenter: PlayerPresenter

    @ObservedObject private var environment: AppEnvironment
    @StateObject private var viewModel: SearchViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: SearchViewModel(environment: environment))
    }

    var body: some View {
        content
            .screenBackground()
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(L.t("search.placeholder"))
            )
            .onChange(of: viewModel.query) { _ in
                viewModel.queryDidChange()
            }
            .navigationDestination(for: Series.self) { series in
                SeriesDetailView(series: series, environment: environment)
            }
            .task {
                await viewModel.prepare()
            }
    }

    // MARK: - İçerik

    @ViewBuilder
    private var content: some View {
        if let message = viewModel.errorMessage, !viewModel.hasQuery {
            ErrorStateView(message: message) {
                Task { await viewModel.retry() }
            }
        } else if !viewModel.hasQuery {
            if viewModel.isLoading {
                LoadingView()
            } else {
                hint
            }
        } else if viewModel.isLoading && viewModel.totalCount == 0 {
            LoadingView()
        } else if viewModel.isEmpty {
            emptyState
        } else {
            results
        }
    }

    /// Henüz iki harf yazılmadığında gösterilen yönlendirme.
    private var hint: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: L.t("search.hint"),
            message: L.t("search.hint.detail")
        )
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "questionmark.circle",
            title: L.t("search.empty.title"),
            message: L.f("search.empty.message", viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)),
            actionTitle: L.t("search.clear")
        ) {
            viewModel.clear()
        }
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                liveSection
                movieSection
                seriesSection
            }
            .padding(.bottom, Theme.Metrics.gutter)
        }
    }

    // MARK: - Bölümler

    @ViewBuilder
    private var liveSection: some View {
        let items = viewModel.liveResults
        if !items.isEmpty {
            SectionHeader(
                title: L.t("search.section.live"),
                subtitle: L.f("search.resultCount", items.count)
            )
            .padding(.top, 8)
            .padding(.bottom, 6)

            rows(items, showsGuide: true)
        }
    }

    @ViewBuilder
    private var movieSection: some View {
        let items = viewModel.movieResults
        if !items.isEmpty {
            SectionHeader(
                title: L.t("search.section.movies"),
                subtitle: L.f("search.resultCount", items.count)
            )
            .padding(.top, 16)
            .padding(.bottom, 6)

            rows(items)
        }
    }

    @ViewBuilder
    private var seriesSection: some View {
        let items = viewModel.seriesResults
        if !items.isEmpty {
            SectionHeader(
                title: L.t("search.section.series"),
                subtitle: L.f("search.resultCount", items.count)
            )
            .padding(.top, 16)
            .padding(.bottom, 6)

            seriesRows(items)
        }
    }

    // MARK: - Satırlar

    /// Canlı ve film sonuçları doğrudan oynatılır; bu yüzden satır kendi
    /// dokunuşunu kurar (`onSelect`).
    private func rows(_ items: [PlayableItem], showsGuide: Bool = false) -> some View {
        ForEach(items) { item in
            if let reference = item.reference {
                MediaRow(
                    title: item.title,
                    subtitle: item.subtitle,
                    imageURL: item.imageURL,
                    badge: badge(for: item),
                    actions: MediaRowActions(
                        isFavorite: environment.favorites.isFavorite(reference),
                        showsFavoriteButton: true,
                        onSelect: { presenter.present(item) },
                        onToggleFavorite: { toggleFavorite(item) }
                    )
                )

                Divider()
                    .overlay(Theme.separator)
                    .padding(.leading, Theme.Metrics.gutter + 46 + Theme.Metrics.rowSpacing)
            }
        }
    }

    /// Dizi sonuçları oynatılmaz; bölüm listesine gidilir. Bu yüzden satır
    /// `NavigationLink` içine alınır ve `onSelect` verilmez — bağlantı
    /// etiketinin içine düğme koymak dokunuşu belirsizleştirir.
    private func seriesRows(_ items: [PlayableItem]) -> some View {
        ForEach(items) { item in
            if case .series(let series) = item {
                NavigationLink(value: series) {
                    MediaRow(
                        title: item.title,
                        subtitle: item.subtitle,
                        imageURL: item.imageURL,
                        actions: MediaRowActions(
                            isFavorite: isFavorite(item),
                            showsFavoriteButton: true,
                            onToggleFavorite: { toggleFavorite(item) }
                        )
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .overlay(Theme.separator)
                    .padding(.leading, Theme.Metrics.gutter + 46 + Theme.Metrics.rowSpacing)
            }
        }
    }

    // MARK: - Yardımcılar

    private func badge(for item: PlayableItem) -> BadgeLabel? {
        guard case .channel(let channel) = item, channel.hasArchive else { return nil }
        return BadgeLabel(text: L.t("live.badge.archive"), style: .neutral)
    }

    private func isFavorite(_ item: PlayableItem) -> Bool {
        guard let reference = item.reference else { return false }
        return environment.favorites.isFavorite(reference)
    }

    private func toggleFavorite(_ item: PlayableItem) {
        guard let playable = item.playable else { return }
        let favorites = environment.favorites
        Task { await favorites.toggle(playable) }
    }
}
