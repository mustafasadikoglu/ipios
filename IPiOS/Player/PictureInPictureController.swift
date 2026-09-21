import AVFoundation
import AVKit

/// Küçük pencere (PiP) denetimi.
///
/// `AVPictureInPictureController` yalnızca somut bir `AVPlayerLayer` üzerinden
/// kurulabildiği için görüntü katmanı hazır olduğunda buraya bağlanır
/// (bkz. `VideoSurfaceView`). Oynatıcı katmanı her yeniden oluşturulduğunda
/// `attach(to:)` yeniden çağrılır ve denetleyici tazelenir; böylece kapanan bir
/// PiP oturumundan sonra ikinci kez açma denemesi sessizce başarısız olmaz.
@MainActor
final class PictureInPictureController: ObservableObject {

    /// Cihaz PiP'i destekliyor mu? (Simülatörde desteklenmez.)
    @Published private(set) var isSupported = false

    /// PiP penceresi şu anda açık mı?
    @Published private(set) var isActive = false

    private var controller: AVPictureInPictureController?
    private let proxy = Delegate()

    /// Kullanıcı PiP penceresindeki "geri dön" düğmesine bastığında çağrılır.
    var onRestore: (() -> Void)?

    init() {
        proxy.onStart = { [weak self] in self?.isActive = true }
        proxy.onStop = { [weak self] in self?.isActive = false }
        proxy.onRestore = { [weak self] in self?.onRestore?() }
    }

    /// Görüntü katmanına bağlanır. Desteklenmeyen cihazlarda sessizce yalnızca
    /// `isSupported` yanlış kalır; arayüz PiP düğmesini çizmez.
    func attach(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isSupported = false
            return
        }

        // Kurucu `failable`: katman hazır değilse `nil` döner. Bu durumda
        // destek bayrağı yanlış bırakılır ve düğme çizilmez.
        guard let controller = AVPictureInPictureController(playerLayer: layer) else {
            isSupported = false
            return
        }
        controller.delegate = proxy
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller
        isSupported = true
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    func stop() {
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    // MARK: - Delege köprüsü

    /// `AVPictureInPictureControllerDelegate` yöntemleri `@MainActor` değildir;
    /// bu köprü geri çağrıları ana aktöre taşır ve döngüsel referansı önlemek
    /// için denetleyiciyi zayıf tutar.
    private final class Delegate: NSObject, AVPictureInPictureControllerDelegate {

        var onStart: (@MainActor () -> Void)?
        var onStop: (@MainActor () -> Void)?
        var onRestore: (@MainActor () -> Void)?

        func pictureInPictureControllerDidStartPictureInPicture(
            _ controller: AVPictureInPictureController
        ) {
            let handler = onStart
            Task { @MainActor in handler?() }
        }

        func pictureInPictureControllerDidStopPictureInPicture(
            _ controller: AVPictureInPictureController
        ) {
            let handler = onStop
            Task { @MainActor in handler?() }
        }

        func pictureInPictureController(
            _ controller: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            let handler = onRestore
            Task { @MainActor in
                handler?()
                completionHandler(true)
            }
        }
    }
}
