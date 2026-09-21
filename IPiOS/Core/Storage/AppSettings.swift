import Foundation
import Combine

/// Kullanıcı tercihleri.
///
/// Yalnızca hassas olmayan ayarlar burada tutulur. Şifreler `KeychainStore`'da,
/// listeler JSON dosyalarında saklanır; burada yalnızca basit anahtarlar var.
@MainActor
final class AppSettings: ObservableObject {

    private enum Key {
        static let autoplayLastChannel = "settings.autoplayLastChannel"
        static let preferredLandscapeFullscreen = "settings.fullscreenOnRotate"
        static let hasAcceptedLegal = "settings.hasAcceptedLegal"
    }

    private let defaults: UserDefaults

    /// Açılışta son izlenen kanalı hazırla.
    @Published var autoplayLastChannel: Bool {
        didSet { defaults.set(autoplayLastChannel, forKey: Key.autoplayLastChannel) }
    }

    /// Cihaz yatay çevrildiğinde tam ekrana geç.
    @Published var fullscreenOnRotate: Bool {
        didSet { defaults.set(fullscreenOnRotate, forKey: Key.preferredLandscapeFullscreen) }
    }

    /// Yasal uyarı ilk açılışta kabul edildi mi?
    ///
    /// Uyarı her açılışta gösterilmez; ancak kullanıcı kabul etmeden uygulama
    /// kullanılamaz. Bu bayrak `UserDefaults`'ta tutulur çünkü hassas veri
    /// değildir (şifreler Keychain'de saklanır).
    @Published var hasAcceptedLegal: Bool {
        didSet { defaults.set(hasAcceptedLegal, forKey: Key.hasAcceptedLegal) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoplayLastChannel = defaults.bool(forKey: Key.autoplayLastChannel)
        self.fullscreenOnRotate = defaults.object(forKey: Key.preferredLandscapeFullscreen) as? Bool ?? true
        self.hasAcceptedLegal = defaults.bool(forKey: Key.hasAcceptedLegal)
    }
}
