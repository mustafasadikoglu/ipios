import SwiftUI

/// Canlı TV sekmesi: kanal listesi, kategori süzgeci ve arama.
///
/// EPG bilgisi liste yüklendikten sonra gelir; gelmediğinde kanallar
/// görünmeye devam eder (yalnızca "şimdi / sırada" satırı boş kalır).
///
/// Araç çubuğunda iki kısayol vardır: favori kanallar ve son izlenenler.
/// İkisi de bu sekmenin içinde açılır çünkü içerik türü zaten canlı yayındır;
/// ayrı sekmeler açmak alt gezinmeyi gereksiz kalabalıklaştırırdı.
struct LiveView: View {

    @EnvironmentObject private var presenter: PlayerPresenter

    @ObservedObject private var environment: AppEnvironment
    @StateObject private var viewModel: LiveViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: LiveViewModel(kind: .live, environment: environment))
    }

    var body: some View {
        content
            .screenBackground()
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(L.t("live.search.placeholder"))
            )
            .onChange(of: viewModel.searchText) { _ in
                viewModel.searchTextDidChange()
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: LiveRoute.favorites) {
                        Image(systemName: "star")
                    }
                    .accessibilityLabel(Text(L.t("favorites.title")))

                    NavigationLink(value: LiveRoute.recents) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel(Text(L.t("recents.title")))
                }
            }
            .navigationDestination(for: LiveRoute.self) { route in
                switch route {
                case .favorites:
                    FavoriteChannelsView(environment: environment)
                case .recents:
                    RecentChannelsView(environment: environment)
                }
            }
            .navigationDestination(for: Channel.self) { channel in
                ChannelDetailView(channel: channel, viewModel: viewModel)
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
                channelList
            }
        }
    }

    private var channelList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                SectionHeader(
                    title: L.t("kind.live"),
                    subtitle: L.f("live.channelCount", viewModel.resultCount)
                )
                .padding(.bottom, 6)

                ForEach(viewModel.visibleItems) { item in
                    if case .channel(let channel) = item {
                        channelRow(channel)

                        Divider()
                            .overlay(Theme.separator)
                            .padding(
                                .leading,
                                Theme.Metrics.gutter + Theme.Metrics.logoSize + Theme.Metrics.rowSpacing
                            )
                    }
                }
            }
            .padding(.bottom, Theme.Metrics.gutter)
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    private func channelRow(_ channel: Channel) -> some View {
        let pair = viewModel.nowAndNext(for: channel)
        return ChannelRow(
            channel: channel,
            now: pair.now,
            next: pair.next,
            isFavorite: environment.favorites.isFavorite(MediaReference(item: channel)),
            isCurrent: isCurrentlyPlaying(channel),
            onSelect: { presenter.present(.channel(channel)) },
            onToggleFavorite: {
                Task { await environment.favorites.toggle(channel) }
            },
            showsGuideButton: true
        )
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "tv.slash",
            title: L.t("live.empty.title"),
            message: L.t("live.empty.message"),
            actionTitle: viewModel.isFiltered ? L.t("common.showAll") : nil
        ) {
            viewModel.clearFilters()
        }
    }

    private func isCurrentlyPlaying(_ channel: Channel) -> Bool {
        guard let item = presenter.presented else { return false }
        return item.id == PlayableItem.channel(channel).id
    }
}

// MARK: - Yollar

/// Canlı TV sekmesi içindeki yardımcı ekranlar.
///
/// `NavigationPath` ile birlikte kullanıldığında `Hashable` olması yeterlidir;
/// kanal listesi de aynı yığına `Channel` değeriyle itilir.
enum LiveRoute: Hashable {
    case favorites
    case recents
}
