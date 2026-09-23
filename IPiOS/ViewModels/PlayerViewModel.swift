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

    /// İz menüsünün açık olup olmadığı.
    ///
    /// **Neden görünümde değil burada:** menü açıkken kontrollerin kendiliğinden
    /// gizlenmesi engellenir (bkz. `scheduleControlsHide`). Bayrak görünümün
    /// `@State`'inde olsaydı gizleme zamanlayıcısı onu göremez, süre dolunca
    /// kontrol katmanı kaybolur ve altında duran menü de anlamsız kalırdı.
    @Published var showsTrackMenu = false

    /// İçerikteki ses/altyazı izleri. Motorun yayını buraya **kopyalanır**.
    ///
    /// **Neden kopya:** SwiftUI iç içe `ObservableObject` yayınlarını kendiliğinden
    /// yaymaz — görünüm yalnızca `viewModel`'i dinlediği için
    /// `viewModel.engine.tracks` doğrudan okunsaydı liste değiştiğinde ekran
    /// yenilenmezdi ve kullanıcı menüyü açtığında **boş** bir liste görürdü.
    @Published private(set) var tracks: PlaybackTrackSet = .empty

    let engine: VLCPlayerEngine
    private let environment: AppEnvironment
    private var controlsTask: Task<Void, Never>?
    private var stateSubscription: AnyCancellable?
    private var tracksSubscription: AnyCancellable?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.engine = environment.player
        observeEngineState()
        observeEngineTracks()
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

    /// Motorun iz listesini görünüme taşır.
    ///
    /// **Neden `@Published` kopya gerekiyor:** `viewModel.engine.tracks` doğrudan
    /// okunsaydı SwiftUI değişimi görmezdi; `engine` bir `ObservableObject` olsa
    /// bile iç içe nesnelerin yayınları üst görünüme **geçmez**. Kullanıcı menüyü
    /// açtığında boş liste görürdü.
    ///
    /// `removeDuplicates()` buraya bilerek konur: libvlc aynı durumu art arda
    /// birkaç kez bildirir (ekleme + seçim + güncelleme) ve her bildirim
    /// listeyi yeniden okur. `PlaybackTrackSet` `Equatable` olduğu için aynı
    /// içerikli okumalar burada elenir ve SwiftUI gereksiz yere yeniden çizmez.
    /// Eşitlik **kimliklere** dayanır (`trackId`), nesne kimliğine değil — bu
    /// yüzden nesnelerin her okumada yeniden üretilmesi sonucu bozmaz.
    private func observeEngineTracks() {
        tracksSubscription = engine.$tracks
            .removeDuplicates()
            .sink { [weak self] set in
                self?.tracks = set
            }
    }

    // MARK: - İz seçimi

    /// Seçilebilecek iz var mı? Kontrol katmanındaki düğme buna bakar.
    var hasTrackChoice: Bool { tracks.hasAnyChoice }

    func selectAudioTrack(id: String) {
        engine.selectAudioTrack(id: id)
        showControls()
    }

    func selectSubtitleTrack(id: String) {
        engine.selectSubtitleTrack(id: id)
        showControls()
    }

    func disableSubtitles() {
        engine.disableSubtitles()
        showControls()
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
        // Yeni içerikte iz menüsü kapalı başlar: önceki içeriğin izleri artık
        // geçersizdir ve açık bir menü boş bir liste gösterirdi.
        showsTrackMenu = false

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
        // Menü açıkken oynatıcı kapatılırsa bayrak açık kalır ve bir sonraki
        // içerik menüsü kapalı çizilmez. Motorun iz listesi `stop()` içinde
        // boşaldığı için açık bir menü boş liste gösterirdi.
        showsTrackMenu = false
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
    ///
    /// **İz menüsü açıkken gizleme yapılmaz.** Menü kontrol katmanına bağlıdır;
    /// kontrol katmanı kaybolursa menü de kaybolur ve seçim yarıda kesilir.
    /// Menü kapandığında gizleme yeniden planlanır.
    func scheduleControlsHide() {
        controlsTask?.cancel()
        guard !showsTrackMenu else { return }
        let delay: Duration = isLive ? .seconds(4) : .seconds(6)
        controlsTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            // Bekleme sırasında menü açılmış olabilir; uyanınca yeniden bakılır.
            guard self?.showsTrackMenu != true else { return }
            withAnimation(.easeOut(duration: 0.2)) { self?.showsControls = false }
        }
    }

    /// İz menüsünü açar/kapatır. Kapatınca gizleme sayacı yeniden başlar.
    func toggleTrackMenu() {
        showsTrackMenu.toggle()
        showControls()
        if showsTrackMenu {
            controlsTask?.cancel()
        } else {
            scheduleControlsHide()
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
