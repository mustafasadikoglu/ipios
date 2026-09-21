import Foundation
import SwiftUI

/// Kaynak ekleme / düzenleme / doğrulama akışını yönetir.
@MainActor
final class SourcesViewModel: ObservableObject {

    /// Kaynak formundaki geçici durum.
    struct Draft {
        var name: String = ""
        var kind: PlaylistSource.Kind = .xtream
        var serverURL: String = ""
        var username: String = ""
        var password: String = ""
        var epgURL: String = ""

        var isEditing: Bool = false
        var editingID: UUID?

        /// Kaynak düzenlenirken şifre alanı boş bırakılabilir; bu durumda
        /// mevcut şifre korunur.
        var passwordTouched: Bool = false
    }

    @Published var draft = Draft()
    @Published private(set) var isValidating = false
    @Published private(set) var validationError: String?
    @Published private(set) var validationWarning: String?
    @Published private(set) var sourceInfo: SourceInfo?

    /// Diskten içe aktarılan M3U dosyası.
    @Published var importedFileURL: URL?
    @Published var importedFileName: String?

    private let repository: SourcesRepository

    init(repository: SourcesRepository) {
        self.repository = repository
    }

    // MARK: - Form

    func startNew(kind: PlaylistSource.Kind = .xtream) {
        draft = Draft(kind: kind)
        validationError = nil
        validationWarning = nil
        sourceInfo = nil
        importedFileURL = nil
        importedFileName = nil
    }

    func startEditing(_ source: PlaylistSource) {
        draft = Draft(
            name: source.name,
            kind: source.kind,
            serverURL: source.baseURL.absoluteString,
            username: source.username ?? "",
            password: "",
            epgURL: source.epgURL?.absoluteString ?? "",
            isEditing: true,
            editingID: source.id,
            passwordTouched: false
        )
        validationError = nil
        validationWarning = nil
        sourceInfo = nil
    }

    var isReadyToSubmit: Bool {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        switch draft.kind {
        case .xtream:
            // Düzenlemede şifre boş bırakılabilir; yeni kayıtta zorunludur.
            let passwordOK = draft.isEditing || !draft.password.isEmpty
            return parsedURL(draft.serverURL) != nil
                && !draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && passwordOK
        case .m3u:
            return importedFileURL != nil || parsedURL(draft.serverURL) != nil
        }
    }

    // MARK: - Doğrulama

    /// Kaynağa bağlanıp kimlik bilgilerini ve içerik sayılarını doğrular.
    func validate() async {
        guard let candidate = makeSource(requirePassword: false) else {
            validationError = AppError.invalidURL.errorDescription
            return
        }

        // Doğrulama sırasında şifre gerekir; düzenlemede boş bırakıldıysa
        // depodaki kayıtlı şifre kullanılır.
        var password = draft.password
        if password.isEmpty, let editingID = draft.editingID,
           let existing = repository.source(with: editingID)?.password {
            password = existing
        }

        isValidating = true
        validationError = nil
        validationWarning = nil
        defer { isValidating = false }

        do {
            let provider = try makeProvider(for: candidate, password: password)
            let info = try await provider.validate()
            sourceInfo = info

            if !info.isValid {
                validationWarning = L.t("sourceinfo.warning.expired")
            }
        } catch let error as AppError {
            sourceInfo = nil
            validationError = error.errorDescription
        } catch {
            sourceInfo = nil
            validationError = error.localizedDescription
        }
    }

    // MARK: - Kaydetme

    /// Formu kaydeder; başarılıysa oluşturulan kaynağın kimliğini döner.
    @discardableResult
    func save() async -> UUID? {
        guard makeSource(requirePassword: false) != nil else {
            validationError = AppError.invalidURL.errorDescription
            return nil
        }

        do {
            if draft.isEditing, let id = draft.editingID,
               let existing = repository.source(with: id) {
                var updated = existing
                updated.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.kind = draft.kind
                if let url = parsedURL(draft.serverURL) { updated.baseURL = url }
                updated.username = draft.kind == .xtream
                    ? draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
                updated.epgURL = parsedURL(draft.epgURL)

                await repository.update(updated)

                if draft.kind == .xtream, !draft.password.isEmpty {
                    try await repository.updatePassword(for: id, password: draft.password)
                }
                return id
            }

            guard let source = makeSource(requirePassword: true) else {
                validationError = AppError.invalidURL.errorDescription
                return nil
            }
            try await repository.add(source, password: draft.kind == .xtream ? draft.password : nil)
            return source.id
        } catch let error as AppError {
            validationError = error.errorDescription
            return nil
        } catch {
            validationError = error.localizedDescription
            return nil
        }
    }

    func delete(_ id: UUID) async {
        await repository.remove(id)
    }

    func clearValidationState() {
        validationError = nil
        validationWarning = nil
        sourceInfo = nil
    }

    // MARK: - Dosya içe aktarma

    func handleImportedFile(_ url: URL) {
        importedFileURL = url
        importedFileName = url.lastPathComponent
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = url.deletingPathExtension().lastPathComponent
        }
        // Dosya seçildiğinde uzak adres alanı anlamsızdır.
        draft.serverURL = ""
        clearValidationState()
    }

    // MARK: - Private

    /// Formdan `PlaylistSource` üretir.
    ///
    /// - Parameter requirePassword: `false` ise şifre alanı boş olsa da kaynak üretilir
    ///   (düzenleme ve doğrulama sırasında mevcut şifre kullanılır).
    private func makeSource(requirePassword: Bool) -> PlaylistSource? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let baseURL: URL
        switch draft.kind {
        case .xtream:
            guard let url = parsedURL(draft.serverURL) else { return nil }
            baseURL = url
        case .m3u:
            if importedFileURL != nil {
                // Dosyadan içe aktarmada adres olarak dosya yolu tutulur.
                baseURL = importedFileURL ?? URL(fileURLWithPath: "/dev/null")
            } else {
                guard let url = parsedURL(draft.serverURL) else { return nil }
                baseURL = url
            }
        }

        let username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)

        return PlaylistSource(
            id: draft.editingID ?? UUID(),
            name: name,
            kind: draft.kind,
            baseURL: baseURL,
            username: (draft.kind == .xtream && !username.isEmpty) ? username : nil,
            credentialKey: nil,
            epgURL: parsedURL(draft.epgURL),
            lastSyncedAt: nil,
            statusNote: nil,
            isEnabled: true
        )
    }

    private func makeProvider(for source: PlaylistSource, password: String) throws -> PlaylistProviding {
        switch source.kind {
        case .xtream:
            return XtreamClient(source: source, password: password)
        case .m3u:
            return M3UPlaylistProvider(source: source, localFileURL: importedFileURL)
        }
    }

    /// Kullanıcı adres alanına "http://" yazmasa da kabul edilir.
    private func parsedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        if let url = URL(string: "http://\(trimmed)"), url.host != nil {
            return url
        }
        return nil
    }
}
