import Foundation
import SwiftUI
import Combine

/// Oynatıcı ekranının durumu.
///
/// Oynatma motoru (`VLCPlayerEngine`) uygulama ömrü boyunca tektir; bu sınıf
/// onu ekrana bağlar: hangi öğenin oynatıldığını, hata durumunu, ekran
/// kilidini ve PiP denetleyicisini yönetir.
@MainActor
final class PlayerViewModel: ObservableObject {

    @Published private(set) var item: PlayableItem?
    @Published var showsControls = true
    @Published var isFullscreen = false
    @Published var showsErrorAlert = false

    let engine: VLCPlayerEngine
    private let environment: AppEnvironment
    private var controlsTask: Task<Void, Never>?
    private var stateSubscription: AnyCancellable?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.engine = environment.player
        observeEngineState()
    }

    /// Motorun durumunu gerçek zamanlı izler.
    ///
    /// Neden gerekli: oynatma hatası `load()` dönmeden çok sonra, ağ yanıtı
    /// geldiğinde ortaya çıkar. Bu abonelik olmadan hata sessizce yutulur ve
    /// kullanıcı siyah ekranda kalırdı (önceki sürümdeki asıl kusur buydu:
    /// hata durumu yalnızca `load()` döndükten hemen sonra kontrol ediliyordu).
    ///
    /// Yalnızca `state` yayınına abone olunur; teşhis bayrağı
    /// (`lastFailureWasUnsupportedFormat`) motorda durum atamasından **önce**
    /// yazıldığı için burada güncel değeri okunur.
    private func observeEngineState() {
        stateSubscription = engine.$state
            .removeDuplicates()
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
    }

    var isPlaying: Bool { engine.state.isPlaying }
    var isLive: Bool { engine.isLive }
    /// Ekran başlığı. Öğe ve motor başlığı boşsa (henüz yükleme yapılmadıysa)
    /// uygulama adına düşülür; böylece başlık hiçbir zaman boş çizilmez.
    var title: String { item?.title ?? engine.currentTitle ?? L.t("app.name") }

    var subtitle: String? {
        guard let item else { return nil }
        if case .episode(let episode) = item { return episode.fullTitle }
        return item.subtitle
    }

    // MARK: - Oynatma

    func play(_ item: PlayableItem) async {
        guard let playable = item.playable else { return }
        self.item = item
        resetErrorState()

        // Kaydedilmiş konum varsa oradan devam edilir.
        let position = environment.recents.position(for: playable)
        await engine.load(playable, startAt: position?.seconds)
        // Hata bildirimi burada kontrol edilmez: `load` döndükten sonra da
        // ortaya çıkabilir. Durum aboneliği (`observeEngineState`) hatayı
        // yakalar ve `handleStateChange` uyarıyı gösterir.
    }

    func retry() async {
        guard let item else { return }
        await play(item)
    }

    func togglePlayPause() {
        engine.togglePlayPause()
        if isPlaying { scheduleControlsHide() } else { showControls() }
    }

    func seek(by seconds: Double) {
        engine.seek(by: seconds)
        showControls()
    }

    func seek(to seconds: Double) {
        engine.seek(to: seconds)
        showControls()
    }

    /// Oynatıcıyı kapatır ve konumu diske yazılmak üzere planlar.
    ///
    /// `persistPosition()` eşzamansızdır; arayüzü bloklamamak için yazma işi
    /// ayrı bir göreve bırakılır. Görünüm kaybolurken de çağrıldığı için
    /// burada `await` edilmesi beklenmez.
    func stop() {
        Task { await engine.persistPosition() }
        engine.stop()
        item = nil
    }

    // MARK: - Kontroller

    func showControls() {
        controlsTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { showsControls = true }
    }

    func toggleControls() {
        if showsControls {
            withAnimation(.easeOut(duration: 0.15)) { showsControls = false }
        } else {
            showControls()
            scheduleControlsHide()
        }
    }

    /// Canlı yayında kontroller daha çabuk gizlenir; VOD'da kullanıcı çubuğu
    /// kullanıyor olabilir.
    func scheduleControlsHide() {
        controlsTask?.cancel()
        let delay: Duration = isLive ? .seconds(4) : .seconds(6)
        controlsTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self?.showsControls = false }
        }
    }

    // MARK: - Hata

    /// Hata uyarısını sıfırlar. Yeni bir öğe yüklenirken eski hatanın ekranda
    /// kalmasını engeller.
    private func resetErrorState() {
        showsErrorAlert = false
    }

    /// Durum aboneliğinden çağrılır.
    ///
    /// `AVPlayer` döneminde ham MPEG-TS için **ayrı** bir uyarı gösteriliyordu:
    /// o çerçeve ham TS konteynerini çözemiyordu ve kullanıcıya "bu biçim
    /// desteklenmiyor" demek gerekiyordu. libvlc ham TS'i sorunsuz oynatır,
    /// dolayısıyla o ayrım tümüyle anlamını yitirdi. Tek bir hata uyarısı
    /// kalır ve metin motorun teşhisinden gelir.
    private func handleStateChange(_ state: PlaybackState) {
        guard case .failed = state else { return }
        showsErrorAlert = true
    }
}
