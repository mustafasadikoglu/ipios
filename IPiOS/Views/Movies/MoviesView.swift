import SwiftUI

/// Filmler sekmesi.
///
/// Üç bölümden oluşur: "İzlemeye Devam Et" şeridi, favori filmler şeridi ve
/// tüm filmler listesi. Şeritler yalnızca içerikleri varsa çizilir; böylece
/// yeni kullanıcı doğrudan film listesini görür.
///
/// Görünüm (ızgara / liste) tercihi kullanıcının: ızgara posterleri öne
/// çıkarırken liste aynı ekranda daha çok kayıt gösterir.
struct MoviesView: View {

    @EnvironmentObject private var presenter: PlayerPresenter

    @ObservedObject private var environment: AppEnvironment
    @StateObject private var viewModel: MoviesViewModel

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
        _viewModel = StateObject(wrappedValue: MoviesViewModel(kind: .movie, environment: environment))
    }

    var body: some View {
        content
            .screenBackground()
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(L.t("movies.search.placeholder"))
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
                movieList
            }
        }
    }

    private var movieList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !viewModel.isFiltered {
                    resumeSection
                    favoritesSection
                }

                SectionHeader(
                    title: L.t("movies.section.all"),
                    subtitle: L.f("movies.movieCount", viewModel.resultCount)
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

    /// Yatay kaydırılan poster şeridi.
    @ViewBuilder
    private var resumeSection: some View {
        let items = viewModel.resumeItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L.t("movies.section.resume"))
                posterStrip(items)
            }
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        let items = viewModel.favoriteMovies
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L.t("movies.section.favorites"))
                posterStrip(items)
            }
            .padding(.bottom, 20)
        }
    }

    private func posterStrip(_ items: [PlayableItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Metrics.rowSpacing) {
                ForEach(items) { item in
                    PosterCard(
                        title: item.title,
                        subtitle: remainingText(for: item),
                        imageURL: item.imageURL,
                        progress: viewModel.position(for: item)?.progress ?? 0,
                        isFavorite: isFavorite(item),
                        showsFavoriteButton: true,
                        onSelect: { present(item) },
                        onToggleFavorite: { toggleFavorite(item) }
                    )
                    .frame(width: 118)
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
                PosterCard(
                    title: item.title,
                    subtitle: item.subtitle,
                    imageURL: item.imageURL,
                    progress: viewModel.position(for: item)?.progress ?? 0,
                    isFavorite: isFavorite(item),
                    showsFavoriteButton: true,
                    onSelect: { present(item) },
                    onToggleFavorite: { toggleFavorite(item) }
                )
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
    }

    private var rows: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.visibleItems) { item in
                MediaRow(
                    title: item.title,
                    subtitle: item.subtitle,
                    imageURL: item.imageURL,
                    progress: viewModel.position(for: item)?.progress ?? 0,
                    actions: MediaRowActions(
                        isFavorite: isFavorite(item),
                        showsFavoriteButton: true,
                        onSelect: { present(item) },
                        onToggleFavorite: { toggleFavorite(item) }
                    )
                )

                Divider()
                    .overlay(Theme.separator)
                    .padding(.leading, Theme.Metrics.gutter + 46 + Theme.Metrics.rowSpacing)
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "film",
            title: L.t("movies.empty.title"),
            message: L.t("movies.empty.message"),
            actionTitle: viewModel.isFiltered ? L.t("common.showAll") : nil
        ) {
            viewModel.clearFilters()
        }
    }

    // MARK: - Yardımcılar

    private func isFavorite(_ item: PlayableItem) -> Bool {
        guard let reference = item.reference else { return false }
        return environment.favorites.isFavorite(reference)
    }

    /// Şeritlerde yalnızca kalan süre gösterilir; yıl ve tür listede zaten var.
    private func remainingText(for item: PlayableItem) -> String? {
        guard let position = viewModel.position(for: item),
              let duration = position.duration,
              duration > position.seconds else { return nil }
        return L.f("recents.remaining", Format.duration(duration - position.seconds))
    }

    /// Dizi kaydı oynatıcıya gitmez; filmler sekmesinde beklenmez, yine de
    /// sessizce yutulmaz.
    private func present(_ item: PlayableItem) {
        guard item.isDirectlyPlayable else { return }
        presenter.present(item)
    }

    private func toggleFavorite(_ item: PlayableItem) {
        guard let playable = item.playable else { return }
        let favorites = environment.favorites
        Task { await favorites.toggle(playable) }
    }
}
