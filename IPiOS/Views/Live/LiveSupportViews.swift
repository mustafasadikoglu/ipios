import SwiftUI

/// Canlı TV sekmesinin yardımcı ekranları: favori kanallar ve son izlenen
/// yayınlar.
///
/// Neden ayrı bir "Favoriler" sekmesi yok: sekmeler içerik türüne göre
/// ayrıldı (Canlı / Film / Dizi). Kullanıcı bir kanalı favorilerken ya da
/// geçmişine dönerken zaten o türün sekmesindedir; bu yüzden süzgeçler
/// sekmenin içinde, araç çubuğunda durur.

// MARK: - Favori kanallar

/// Yalnızca favoriye eklenmiş kanalları gösterir.
struct FavoriteChannelsView: View {

    @ObservedObject private var environment: AppEnvironment
    @EnvironmentObject private var presenter: PlayerPresenter

    @StateObject private var viewModel: FavoritesViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: FavoritesViewModel(environment: environment))
    }

    var body: some View {
        content
            .screenBackground()
            .navigationTitle(L.t("favorites.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.selectedItems.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L.t("common.delete"), role: .destructive) {
                            viewModel.removeAll()
                        }
                    }
                }
            }
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty {
            EmptyStateView(
                icon: "star",
                title: L.t("favorites.empty.title"),
                message: L.t("favorites.empty.message")
            )
        } else if viewModel.isWaitingForLibrary && viewModel.isLoading {
            LoadingView()
        } else if let message = viewModel.errorMessage {
            ErrorStateView(message: message) {
                Task { await viewModel.loadIfNeeded() }
            }
        } else if viewModel.selectedItems.isEmpty {
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: L.t("favorites.empty.title"),
                message: L.t("favorites.unavailable")
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                SectionHeader(
                    title: L.t("favorites.title"),
                    subtitle: L.f("live.channelCount", viewModel.selectedItems.count)
                )
                .padding(.bottom, 6)

                ForEach(viewModel.selectedItems) { item in
                    MediaRow(
                        title: item.title,
                        subtitle: item.subtitle,
                        imageURL: item.imageURL,
                        badge: badge(for: item),
                        actions: MediaRowActions(
                            isFavorite: true,
                            showsFavoriteButton: true,
                            onSelect: { presenter.present(item) },
                            onToggleFavorite: { viewModel.remove(item) }
                        )
                    )

                    Divider()
                        .overlay(Theme.separator)
                        .padding(
                            .leading,
                            Theme.Metrics.gutter + 46 + Theme.Metrics.rowSpacing
                        )
                }
            }
            .padding(.bottom, Theme.Metrics.gutter)
        }
    }

    private func badge(for item: PlayableItem) -> BadgeLabel? {
        guard case .channel(let channel) = item, channel.hasArchive else { return nil }
        return BadgeLabel(text: L.t("live.badge.archive"), style: .neutral)
    }
}

// MARK: - Son izlenen canlı yayınlar

/// Yakın zamanda açılmış kanalları, varsa kaldığı yerden devam bilgisiyle
/// listeler.
struct RecentChannelsView: View {

    @ObservedObject private var environment: AppEnvironment
    @EnvironmentObject private var presenter: PlayerPresenter

    @StateObject private var viewModel: RecentsViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: RecentsViewModel(environment: environment))
    }

    /// Yalnızca canlı yayın türündeki kayıtlar.
    private var entries: [RecentsViewModel.Entry] {
        viewModel.allEntries.filter { $0.reference.kind == .live }
    }

    var body: some View {
        content
            .screenBackground()
            .navigationTitle(L.t("recents.title"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty || entries.isEmpty {
            EmptyStateView(
                icon: "clock",
                title: L.t("recents.title"),
                message: L.t("recents.empty")
            )
        } else if let message = viewModel.errorMessage {
            ErrorStateView(message: message) {
                Task { await viewModel.loadIfNeeded() }
            }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.needsLibrary {
                    Text(L.t("recents.needsLibrary"))
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Metrics.gutter)
                        .padding(.bottom, 8)
                }

                SectionHeader(
                    title: L.t("recents.title"),
                    subtitle: L.f("live.channelCount", entries.count)
                )
                .padding(.bottom, 6)

                ForEach(entries) { entry in
                    row(for: entry)

                    Divider()
                        .overlay(Theme.separator)
                        .padding(
                            .leading,
                            Theme.Metrics.gutter + 46 + Theme.Metrics.rowSpacing
                        )
                }
            }
            .padding(.bottom, Theme.Metrics.gutter)
        }
        .refreshable {
            await viewModel.loadIfNeeded()
        }
    }

    /// Liste çözülemediyse (kaynak silinmiş ya da henüz yüklenmemişse) satır
    /// yalnızca başlıkla gösterilir; kullanıcı yine de neyi izlediğini görür.
    @ViewBuilder
    private func row(for entry: RecentsViewModel.Entry) -> some View {
        if let item = entry.item {
            MediaRow(
                title: item.title,
                subtitle: item.subtitle,
                imageURL: item.imageURL,
                progress: entry.progress,
                actions: MediaRowActions(
                    isFavorite: environment.favorites.isFavorite(entry.reference),
                    showsFavoriteButton: true,
                    onSelect: { presenter.present(item) },
                    onToggleFavorite: {
                        Task {
                            if let playable = item.playable {
                                await environment.favorites.toggle(playable)
                            }
                        }
                    }
                )
            )
        } else {
            MediaRow(
                title: entry.reference.title,
                subtitle: L.t("favorites.unavailable"),
                imageURL: entry.reference.imageURL,
                actions: MediaRowActions()
            )
        }
    }
}
