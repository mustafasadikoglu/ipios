import SwiftUI

/// Diziler sekmesi.
///
/// Bölümler burada gösterilmez: bir diziye dokunulduğunda detay ekranı açılır
/// ve sezon/bölüm listesi orada yüklenir. Bu, Xtream'in çalışma biçiminden
/// gelir — bölümler liste yanıtında değil, dizi başına ayrı bir istekte gelir.
struct SeriesView: View {

    @ObservedObject private var environment: AppEnvironment
    @StateObject private var viewModel: SeriesViewModel

    @State private var layout: Layout = .grid
    enum Layout: String, CaseIterable, Identifiable {
        case grid
        case list

        var id: String { rawValue }

        var title: String {
            switch self {
            case .grid: return L.t("movies.grid")
            case .list: return L.t("movies.list")
            }
        }

        var iconName: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: SeriesViewModel(kind: .series, environment: environment))
    }

    var body: some View {
        content
            .screenBackground()
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(L.t("series.search.placeholder"))
            )
            .onChange(of: viewModel.searchText) { _ in
                viewModel.searchTextDidChange()
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.showsFavoritesOnly.toggle()
                    } label: {
                        Image(systemName: viewModel.showsFavoritesOnly ? "star.fill" : "star")
                            .foregroundStyle(
                                viewModel.showsFavoritesOnly ? Theme.accent : Theme.textSecondary
                            )
                    }
                    .accessibilityLabel(
                        Text(L.t(viewModel.showsFavoritesOnly ? "favorites.remove" : "favorites.add"))
                    )

                    Button {
                        layout = (layout == .grid) ? .list : .grid
                    } label: {
                        Image(systemName: layout.iconName)
                    }
                    .accessibilityLabel(Text(layout.title))
                }
            }
            .navigationDestination(for: Series.self) { series in
                SeriesDetailView(series: series, environment: environment)
            }
            .task {
                await viewModel.loadIfNeeded()
            }
    }

    // MARK: - İçerik

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            CategoryChipBar(categories: viewModel.categories, selection: $viewModel.selectedCategoryID)

            if let message = viewModel.errorMessage {
                ErrorStateView(message: message) {
                    Task { await viewModel.reload() }
                }
            } else if viewModel.isLoading && viewModel.allItems.isEmpty {
                LoadingView()
            } else if viewModel.visibleItems.isEmpty {
                emptyState
            } else {
                seriesList
            }
        }
    }

    private var seriesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !viewModel.isFiltered {
                    continueSection
                    favoritesSection
                }

                SectionHeader(
                    title: L.t("series.section.all"),
                    subtitle: L.f("series.seriesCount", viewModel.resultCount)
                )
                .padding(.top, viewModel.isFiltered ? 0 : 8)
                .padding(.bottom, 10)

                if layout == .grid {
                    grid
                } else {
                    rows
                }
            }
            .padding(.bottom, Theme.Metrics.gutter)
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    // MARK: - Şeritler

    @ViewBuilder
    private var continueSection: some View {
        let items = viewModel.continueWatching
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L.t("series.section.continue"))
                posterStrip(items)
            }
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        let items = viewModel.favoriteSeries
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L.t("series.section.favorites"))
                posterStrip(items)
            }
            .padding(.bottom, 20)
        }
    }

    /// Kart `NavigationLink` içine alınır ve karta kendi düğmesi kurulmaz
    /// (`onSelect: nil`). Böylece diziye dokunmak sezon/bölüm ekranını açar.
    private func posterStrip(_ items: [PlayableItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Metrics.rowSpacing) {
                ForEach(items) { item in
                    if case .series(let series) = item {
                        NavigationLink(value: series) {
                            PosterCard(
                                title: item.title,
                                subtitle: series.year ?? series.genre,
                                imageURL: item.imageURL,
                                isFavorite: isFavorite(item),
                                showsFavoriteButton: true,
                                onToggleFavorite: { toggleFavorite(item) }
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: 118)
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
        }
    }

    // MARK: - Ana liste

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: Theme.Metrics.rowSpacing)],
            spacing: Theme.Metrics.rowSpacing + 10
        ) {
            ForEach(viewModel.visibleItems) { item in
                if case .series(let series) = item {
                    NavigationLink(value: series) {
                        PosterCard(
                            title: item.title,
                            subtitle: series.year ?? series.genre,
                            imageURL: item.imageURL,
                            isFavorite: isFavorite(item),
                            showsFavoriteButton: true,
                            onToggleFavorite: { toggleFavorite(item) }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
    }

    private var rows: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.visibleItems) { item in
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
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "rectangle.stack",
            title: L.t("series.empty.title"),
            message: L.t("series.empty.message"),
            actionTitle: viewModel.isFiltered ? L.t("common.showAll") : nil
        ) {
            viewModel.clearFilters()
        }
    }

    // MARK: - Yardımcılar

    /// Dizi oynatılmaz, detay ekranına gidilir. Gezinme `Series` değeriyle
    /// yapılır; hedef ekran `navigationDestination(for: Series.self)` ile
    /// bu görünümün üzerindeki yığında tanımlıdır.
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
