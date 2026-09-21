import SwiftUI

/// Uygulamanın kök görünümü ve açılış kapıları.
///
/// Sırasıyla şunlar kontrol edilir:
/// 1. Yasal uyarı kabul edilmiş mi? (ilk açılışta zorunlu)
/// 2. Depolar diskten okundu mu?
/// 3. Okuma sırasında hata oluştu mu?
/// 4. Hiç kaynak yok mu? (kaynak ekleme daveti)
/// 5. Hepsi tamamsa ana sekme yapısı.
///
/// Oynatıcı burada, ağacın en üstünde sunulur; böylece hangi sekmeden
/// başlatılırsa başlatılsın tek bir oynatıcı örneği kullanılır.
struct RootView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var presenter: PlayerPresenter
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if !settings.hasAcceptedLegal {
                LegalView {
                    settings.hasAcceptedLegal = true
                }
                .transition(.opacity)
            } else if let message = environment.startupError {
                // Hata kapısı `isReady` kapısından önce gelir: okuma
                // başarısız olduğunda `isReady` hiçbir zaman doğru olmaz ve
                // sıralama ters olsaydı ekran sonsuza dek yüklemede kalırdı.
                ErrorStateView(message: message, retryTitle: L.t("startup.retry")) {
                    Task { await environment.bootstrap() }
                }
                .screenBackground()
            } else if !environment.isReady {
                LoadingView()
                    .screenBackground()
            } else if environment.needsSource {
                NoSourceView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: environment.isReady)
        .animation(.easeInOut(duration: 0.2), value: settings.hasAcceptedLegal)
        .task {
            await environment.bootstrap()
        }
        .fullScreenCover(item: $presenter.presented) { item in
            // Oynatıcı da ayarlara (yatayda tam ekran) ve ortama ihtiyaç duyar;
            // `fullScreenCover` ayrı bir sunum ağacı olduğu için ortam
            // nesneleri burada açıkça yeniden verilir.
            PlayerView(item: item)
                .environmentObject(presenter)
                .environmentObject(environment)
                .environmentObject(settings)
        }
    }
}

/// Hiç kaynak eklenmemişken gösterilen davet ekranı.
private struct NoSourceView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @State private var showsAddSource = false

    var body: some View {
        EmptyStateView(
            icon: "antenna.radiowaves.left.and.right",
            title: L.t("onboarding.title"),
            message: L.t("onboarding.subtitle"),
            actionTitle: L.t("onboarding.action.add")
        ) {
            showsAddSource = true
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            Text(L.t("onboarding.note"))
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Metrics.gutter * 2)
                .padding(.bottom, Theme.Metrics.gutter)
        }
        .sheet(isPresented: $showsAddSource) {
            AddSourceView(repository: environment.sources)
        }
    }
}
