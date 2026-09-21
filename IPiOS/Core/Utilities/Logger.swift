import Foundation
import OSLog

/// Basit, kategorize edilmiş loglama yardımcısı.
///
/// Kullanıcı adı/şifre gibi hassas veriler loglanmaz; URL'ler
/// `Logger.redacted(_:)` ile maskelenir.
enum Log {
    private static let subsystem = "com.mustafa.ipios"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let player = Logger(subsystem: subsystem, category: "player")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let epg = Logger(subsystem: subsystem, category: "epg")

    /// Xtream URL'lerindeki `username` ve `password` parametrelerini maskeler.
    static func redacted(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<geçersiz url>"
        }
        let sensitive: Set<String> = ["username", "password", "token", "api_key"]
        components.queryItems = components.queryItems?.map { item in
            sensitive.contains(item.name.lowercased())
                ? URLQueryItem(name: item.name, value: "***")
                : item
        }
        return components.string ?? "<geçersiz url>"
    }
}
