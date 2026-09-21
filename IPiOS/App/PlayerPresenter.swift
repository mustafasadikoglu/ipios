import SwiftUI

/// Oynatıcının hangi ekrandan açıldığından bağımsız olarak yönetildiği yer.
///
/// Neden gerekli: oynatma kanal listesinden, film ızgarasından, dizi
/// detayından ve arama sonuçlarından başlatılabilir. Her ekranda ayrı bir
/// `fullScreenCover` kurmak yerine tüm istekler burada toplanır; oynatıcı
/// uygulamanın en üst katmanında tek bir kez sunulur.
///
/// Tek örnek olması ayrıca motorun (`AVPlayerEngine`) ekran değişse bile
/// kesintisiz devam etmesini sağlar.
@MainActor
final class PlayerPresenter: ObservableObject {

    /// Sunulacak öğe. `nil` olduğunda oynatıcı kapalıdır.
    @Published var presented: PlayableItem?

    let viewModel: PlayerViewModel

    init(environment: AppEnvironment) {
        self.viewModel = PlayerViewModel(environment: environment)
    }

    /// Oynatıcıyı açar.
    ///
    /// Dizi gibi doğrudan oynatılamayan öğeler (önce bölüm seçilmelidir)
    /// sessizce yok sayılır; böylece çağıran taraf tür kontrolü yapmak
    /// zorunda kalmaz.
    func present(_ item: PlayableItem) {
        guard item.isDirectlyPlayable else { return }
        presented = item
        Task { await viewModel.play(item) }
    }

    func dismiss() {
        viewModel.stop()
        presented = nil
    }
}
