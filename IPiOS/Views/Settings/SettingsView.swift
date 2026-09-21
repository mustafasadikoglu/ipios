import SwiftUI

/// Ayarlar sekmesi.
///
/// Dört bölümden oluşur: kaynak yönetimi (ekle / düzenle / aktif yap / sil),
/// oynatma tercihleri, veri temizleme ve hakkında. Kaynak listesi doğrudan
/// `SourcesRepository`'den okunur; ekleme ve silme işlemleri depoyu güncellediği
/// için liste kendiliğinden tazelenir.
struct SettingsView: View {

    @ObservedObject private var environment: AppEnvironment

    /// Tercihler ayrı bir ortam nesnesidir: kök görünümdeki yasal kapı ile
    /// aynı örneği paylaşır.
    @ObservedObject private var settings: AppSettings

    @State private var showsAddSource = false
    @State private var editingSource: PlaylistSource?

    /// Silme onayları tek bir durum üzerinden yürür.
    ///
    /// Neden tek: her düğmeye ayrı bir `confirmationDialog` bağlamak, satırlar
    /// yeniden çizildiğinde hangi diyaloğun açık olduğunu belirsizleştirir.
    /// Tek bir enum, aynı anda yalnızca bir onayın açık olmasını garanti eder.
    @State private var pendingRemoval: Removal?
    @State private var showsClearedAlert = false

    private enum Removal: Identifiable {
        case source(UUID)
        case recents
        case positions
        case favorites

        var id: String {
            switch self {
            case .source(let id): return "source-\(id.uuidString)"
            case .recents: return "recents"
            case .positions: return "positions"
            case .favorites: return "favorites"
            }
        }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settings = environment.settings
    }

    var body: some View {
        Form {
            sourcesSection
            playbackSection
            dataSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .sheet(isPresented: $showsAddSource) {
            AddSourceView(repository: environment.sources)
        }
        .sheet(item: $editingSource) { source in
            AddSourceView(repository: environment.sources, editingSource: source)
        }
        .confirmationDialog(
            prompt(for: pendingRemoval),
            isPresented: isRemovalPresented,
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { removal in
            Button(L.t("common.delete"), role: .destructive) {
                Task { await perform(removal) }
            }
            Button(L.t("common.cancel"), role: .cancel) {}
        }
        .alert(L.t("settings.cleared"), isPresented: $showsClearedAlert) {
            Button(L.t("common.ok")) {}
        }
    }

    // MARK: - Kaynaklar

    private var sourcesSection: some View {
        Section {
            ForEach(environment.sources.sources) { source in
                sourceRow(source)
            }

            Button {
                showsAddSource = true
            } label: {
                Label(L.t("sources.action.add"), systemImage: "plus.circle")
            }
        } header: {
            Text(L.t("settings.section.sources"))
        } footer: {
            if environment.sources.sources.isEmpty {
                Text(L.t("sources.empty.message"))
            } else {
                Text(L.t("settings.sources.footer"))
            }
        }
    }

    private func sourceRow(_ source: PlaylistSource) -> some View {
        let isActive = environment.sources.activeSourceID == source.id

        return HStack(spacing: Theme.Metrics.rowSpacing) {
            Image(systemName: source.kind.iconName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isActive ? Theme.accent : Theme.textTertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    if isActive {
                        BadgeLabel(text: L.t("sources.active"), style: .accent)
                    }
                }

                Text(source.kind.displayName)
                    .font(Theme.Fonts.rowSubtitle)
                    .foregroundStyle(Theme.textSecondary)

                if let synced = source.lastSyncedAt {
                    Text(L.f("sources.synced.value", Format.relative(synced)))
                        .font(Theme.Fonts.numeric)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        // Satırın tamamı düzenlemeyi açar. Aktif yapma ve silme kaydırma
        // eylemlerinde durur; böylece yanlışlıkla kaynak silmek zorlaşır.
        .onTapGesture { editingSource = source }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingRemoval = .source(source.id)
            } label: {
                Label(L.t("common.delete"), systemImage: "trash")
            }

            if !isActive {
                Button {
                    Task { await environment.sources.setActive(source.id) }
                } label: {
                    Label(L.t("sources.action.setActive"), systemImage: "checkmark.circle")
                }
                .tint(Theme.accent)
            }
        }
    }

    // MARK: - Oynatma

    private var playbackSection: some View {
        Section {
            Toggle(L.t("settings.autoplay"), isOn: $settings.autoplayLastChannel)

            Toggle(L.t("settings.fullscreenOnRotate"), isOn: $settings.fullscreenOnRotate)
        } header: {
            Text(L.t("settings.section.playback"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("settings.autoplay.footer"))
                Text(L.t("settings.fullscreenOnRotate.footer"))
            }
        }
    }

    // MARK: - Veriler

    private var dataSection: some View {
        Section {
            Button(L.t("settings.clearRecents"), role: .destructive) {
                pendingRemoval = .recents
            }

            Button(L.t("settings.clearPositions"), role: .destructive) {
                pendingRemoval = .positions
            }

            Button(L.t("settings.clearFavorites"), role: .destructive) {
                pendingRemoval = .favorites
            }
        } header: {
            Text(L.t("settings.section.data"))
        }
    }

    // MARK: - Hakkında

    private var aboutSection: some View {
        Section {
            LabeledContent(L.t("settings.version"), value: Self.appVersion)

            NavigationLink {
                LegalDetailView()
            } label: {
                Text(L.t("settings.legal"))
            }
        } header: {
            Text(L.t("settings.section.about"))
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return L.f("settings.version.value", short, build)
    }

    // MARK: - Silme akışı

    private var isRemovalPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    private func prompt(for removal: Removal?) -> String {
        switch removal {
        case .source: return L.t("sources.delete.confirm")
        case .recents: return L.t("settings.clearRecents.confirm")
        case .positions: return L.t("settings.clearPositions.confirm")
        case .favorites: return L.t("settings.clearFavorites.confirm")
        case nil: return L.t("common.delete")
        }
    }

    private func perform(_ removal: Removal) async {
        switch removal {
        case .source(let id):
            await environment.sources.remove(id)

        case .recents:
            await environment.recents.clearRecents()
            showsClearedAlert = true

        case .positions:
            await environment.recents.clearAllPositions()
            showsClearedAlert = true

        case .favorites:
            await environment.favorites.removeAll()
            showsClearedAlert = true
        }
        pendingRemoval = nil
    }
}

// MARK: - Yasal metin

/// Ayarlardan okunabilen tam yasal uyarı metni.
///
/// İlk açılıştaki ekranla aynı anahtarları kullanır; orada olduğu gibi burada
/// da tek bir çıkış yolu vardır.
struct LegalDetailView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing * 1.5) {
                Text(L.t("settings.legal.body"))
                    .font(Theme.Fonts.rowSubtitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L.t("legal.body"))
                    .font(Theme.Fonts.rowSubtitle)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L.t("settings.legal.footer"))
                    .font(Theme.Fonts.numeric)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(Theme.Metrics.gutter * 1.5)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(L.t("settings.legal"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
