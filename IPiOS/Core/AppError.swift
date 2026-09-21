import Foundation

/// Uygulama genelinde kullanılan, kullanıcıya gösterilebilir hata tipi.
///
/// Metinler `Localizable.strings` içinden gelir; kodda sabit metin yoktur.
enum AppError: LocalizedError, Equatable {
    case invalidURL
    case network(underlying: String)
    case timeout
    case unauthorized
    case notFound
    case server(status: Int)
    case decoding(context: String)
    case badCredentials
    case sourceUnreachable
    case playlistEmpty
    case playbackFailed(reason: String)
    case cancelled
    case storage(underlying: String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L.t("error.invalidURL")
        case .network(let underlying):
            return L.f("error.network", underlying)
        case .timeout:
            return L.t("error.timeout")
        case .unauthorized, .badCredentials:
            return L.t("error.unauthorized")
        case .notFound:
            return L.t("error.notFound")
        case .server(let status):
            return L.f("error.server", status)
        case .decoding(let context):
            return L.f("error.decoding", context)
        case .sourceUnreachable:
            return L.t("error.sourceUnreachable")
        case .playlistEmpty:
            return L.t("error.playlistEmpty")
        case .playbackFailed(let reason):
            return L.f("error.playbackFailed", reason)
        case .cancelled:
            return L.t("error.cancelled")
        case .storage(let underlying):
            return L.f("error.storage", underlying)
        case .unknown:
            return L.t("error.unknown")
        }
    }

    /// Yeniden deneme anlamlı olan hatalar için `true` döner.
    var isRetryable: Bool {
        switch self {
        case .timeout, .network, .server, .sourceUnreachable:
            return true
        default:
            return false
        }
    }
}
