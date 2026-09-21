import Foundation
import SwiftUI
import AVKit

/// Oynatıcı ekranının durumu.
///
/// Oynatma motoru (`AVPlayerEngine`) uygulama ömrü boyunca tektir; bu sınıf
/// onu ekrana bağlar: hangi öğenin oynatıldığını, hata durumunu, ekran
/// kilidini ve PiP denetleyicisini yönetir.
@MainActor
final class PlayerViewModel: ObservableObject {

    @Published private(set) var item: PlayableItem?
    @Published var showsControls = true
    @Published var isFullscreen = false
    @Published var showsErrorAlert = false
    @Published var showsTSWarning = false

    let engine: AVPlayerEngine
    private let environment: AppEnvironment
    private var controlsTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.engine = environment.player
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
        showsErrorAlert = false

        // Kaydedilmiş konum varsa oradan devam edilir.
        let position = environment.recents.position(for: playable)
        await engine.load(playable, startAt: position?.seconds)

        if case .failed = engine.state {
            showsErrorAlert = true
        }
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

    func handleStateChange() {
        switch engine.state {
        case .failed: showsErrorAlert = true
        default: break
        }
    }
}
