import SwiftUI

/// Uygulamanın giriş noktası.
///
/// Tek bir `AppEnvironment` üretilir ve tüm ağaç boyunca `@StateObject`
/// olarak taşınır: depolar (kaynaklar, favoriler, geçmiş, içerik listesi) ve
/// oynatıcı motoru uygulama ömrü boyunca tek örnek olmalıdır.
@main
struct IPiOSApp: App {

    @StateObject private var environment: AppEnvironment
    @StateObject private var presenter: PlayerPresenter

    init() {
        // `PlayerPresenter` ortama bağımlı olduğundan `@StateObject`
        // başlatıcısıyla doğrudan kurulamaz; bu yüzden ikisi de burada
        // üretilip atanır.
        let environment = AppEnvironment()
        _environment = StateObject(wrappedValue: environment)
        _presenter = StateObject(wrappedValue: PlayerPresenter(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(presenter)
                .environmentObject(environment.settings)
                .preferredColorScheme(.dark)
        }
    }
}
