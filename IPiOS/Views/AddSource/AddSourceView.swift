import SwiftUI
import UniformTypeIdentifiers

/// Kaynak ekleme / düzenleme formu.
///
/// İki kaynak türü desteklenir: Xtream Codes (sunucu + kullanıcı + şifre) ve
/// M3U listesi (uzak adres ya da cihazdaki dosya). Şifre yalnızca bu formda
/// alınır ve `SourcesRepository` üzerinden Keychain'e yazılır; forma geri
/// yüklenmez.
struct AddSourceView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    /// Düzenlenecek kaynak verilirse form "düzenle" kipinde açılır.
    let editingSource: PlaylistSource?

    @StateObject private var viewModel: SourcesViewModel

    @State private var showsFileImporter = false
    @State private var showsDeleteConfirm = false
    @State private var saveError: String?

    /// Depo dışarıdan verilir: form, uygulamanın tek `SourcesRepository`
    /// örneğini kullanmalıdır. Yeni bir örnek üretilseydi kaynak listesi
    /// bellekte ikiye ayrılır ve eklenen kaynak ana ekranda görünmezdi.
    init(repository: SourcesRepository, editingSource: PlaylistSource? = nil) {
        self.editingSource = editingSource
        _viewModel = StateObject(wrappedValue: SourcesViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.draft.isEditing {
                    editingHeader
                }

                kindSection
                connectionSection

                if viewModel.draft.kind == .xtream {
                    credentialsSection
                }

                epgSection
                validationSection
                legalSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(
                L.t(viewModel.draft.isEditing ? "addsource.title.edit" : "addsource.title.new")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.save")) {
                        Task { await save() }
                    }
                    .disabled(!viewModel.isReadyToSubmit)
                }
                if viewModel.draft.isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button(L.t("common.delete"), role: .destructive) {
                            showsDeleteConfirm = true
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: Self.playlistTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { viewModel.handleImportedFile(url) }
                case .failure:
                    saveError = L.t("addsource.file.pickError")
                }
            }
            .confirmationDialog(
                L.t("sources.delete.confirm"),
                isPresented: $showsDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(L.t("common.delete"), role: .destructive) {
                    Task { await deleteSource() }
                }
                Button(L.t("common.cancel"), role: .cancel) {}
            }
        }
        .onAppear {
            if let editingSource {
                viewModel.startEditing(editingSource)
            } else {
                viewModel.startNew()
            }
        }
        .alert(L.t("player.error.title"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(L.t("common.ok")) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Bölümler

    private var editingHeader: some View {
        Section {
            Text(L.t("addsource.password.keepHint"))
                .font(Theme.Fonts.rowSubtitle)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var kindSection: some View {
        Section(L.t("addsource.field.kind")) {
            Picker(L.t("addsource.field.kind"), selection: $viewModel.draft.kind) {
                ForEach(PlaylistSource.Kind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.iconName).tag(kind)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(viewModel.draft.isEditing)
            .onChange(of: viewModel.draft.kind) { _ in
                viewModel.clearValidationState()
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        Section(L.t("addsource.section.connection")) {
            TextField(L.t("addsource.field.name"), text: $viewModel.draft.name)
                .textInputAutocapitalization(.words)

            switch viewModel.draft.kind {
            case .xtream:
                TextField(
                    L.t("addsource.field.server"),
                    text: $viewModel.draft.serverURL,
                    prompt: Text(L.t("addsource.field.server.placeholder"))
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            case .m3u:
                TextField(
                    L.t("addsource.field.server"),
                    text: $viewModel.draft.serverURL,
                    prompt: Text(L.t("addsource.field.server.placeholder"))
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    showsFileImporter = true
                } label: {
                    Label(L.t("addsource.action.pickFile"), systemImage: "folder")
                }

                if let name = viewModel.importedFileName {
                    Text(L.f("addsource.action.picked", name))
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var credentialsSection: some View {
        Section {
            TextField(L.t("addsource.field.username"), text: $viewModel.draft.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField(L.t("addsource.field.password"), text: $viewModel.draft.password)
        } footer: {
            Text(L.t("addsource.password.hint"))
        }
    }

    private var epgSection: some View {
        Section {
            TextField(L.t("addsource.field.epg"), text: $viewModel.draft.epgURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            HStack {
                Text(L.t("addsource.field.epg"))
                Spacer()
                Text(L.t("addsource.field.epg.optional"))
                    .font(Theme.Fonts.badge)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        Section {
            Button {
                Task { await viewModel.validate() }
            } label: {
                HStack {
                    if viewModel.isValidating {
                        ProgressView().controlSize(.small)
                        Text(L.t("addsource.testing"))
                    } else {
                        Label(L.t("addsource.action.test"), systemImage: "checkmark.shield")
                    }
                }
            }
            .disabled(viewModel.isValidating || !viewModel.isReadyToSubmit)

            if let info = viewModel.sourceInfo {
                sourceInfoRows(info)
            }

            if let warning = viewModel.validationWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(Theme.Fonts.rowSubtitle)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let error = viewModel.validationError {
                Label(error, systemImage: "xmark.circle")
                    .font(Theme.Fonts.rowSubtitle)
                    .foregroundStyle(Theme.liveRed)
            }
        }
    }

    @ViewBuilder
    private func sourceInfoRows(_ info: SourceInfo) -> some View {
        if let status = info.status {
            LabeledContent(L.t("sourceinfo.status"), value: status)
        }
        if let expiry = info.expiryText {
            LabeledContent(L.t("sourceinfo.expires"), value: expiry)
        }
        if let connections = info.maxConnections {
            LabeledContent(L.t("sourceinfo.connections"), value: "\(connections)")
        }
        if info.liveCount != nil || info.movieCount != nil || info.seriesCount != nil {
            LabeledContent(
                L.t("sourceinfo.counts"),
                value: L.f(
                    "sourceinfo.counts.value",
                    info.liveCount ?? 0,
                    info.movieCount ?? 0,
                    info.seriesCount ?? 0
                )
            )
        }
    }

    private var legalSection: some View {
        Section {
            Text(L.t("addsource.legal"))
                .font(Theme.Fonts.rowSubtitle)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Eylemler

    private func save() async {
        guard await viewModel.save() != nil else {
            saveError = viewModel.validationError
            return
        }
        dismiss()
    }

    private func deleteSource() async {
        guard let id = viewModel.draft.editingID else { return }
        await viewModel.delete(id)
        dismiss()
    }

    /// Dosyalar uygulamasında `.m3u` uzantısı standart bir türe karşılık
    /// gelmediğinden hem uzantıdan hem de metinden türetilir.
    private static var playlistTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .data]
        if let m3u = UTType(filenameExtension: "m3u") { types.insert(m3u, at: 0) }
        if let m3u8 = UTType(filenameExtension: "m3u8") { types.insert(m3u8, at: 0) }
        return types
    }
}
