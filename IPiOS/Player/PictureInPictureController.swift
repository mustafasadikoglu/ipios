import Foundation
import UIKit
import VLCKit

/// Küçük pencere (PiP) denetimi — **VLCKit geçişinde devre dışı**.
///
/// **Neden boş:** `AVPlayer` döneminde PiP, `AVPictureInPictureController`'ın
/// somut bir `AVPlayerLayer` üzerine kurulmasıyla elde ediliyordu. libvlc
/// görüntüyü `AVPlayerLayer`'a değil, kendi çizdiği bir alt katmana yazar;
/// dolayısıyla o yol artık kullanılamaz.
///
/// VLCKit 4.0 kendi PiP API'sini sunar (`Headers/Public/Video/VLCDrawable.h`):
///
/// - `VLCPictureInPictureDrawable` — `mediaController` ve
///   `pictureInPictureReady` üyeleriyle oynatıcıyı PiP'e tanıtır.
/// - `VLCPictureInPictureMediaControlling` — PiP penceresinin oynatma
///   çağrıları: `play`, `pause`, `seekBy:completion:`, `mediaLength`,
///   `mediaTime`, `isMediaSeekable`, `isMediaPlaying`.
/// - `VLCPictureInPictureWindowControlling` — `stateChangeEventHandler`
///   bloğu ile `startPictureInPicture`/`stopPictureInPicture` ve
///   `invalidatePlaybackState`.
///
/// **Neden şimdi yazılmadı:** bu protokollerin Swift'e köprülenmiş imzaları
/// (özellikle `dispatch_block_t` alan `seekBy:completion:` ve blok döndüren
/// `pictureInPictureReady`) derleyici olmadan doğrulanamaz. Yanlış bir imza
/// tahmini, çalışma anında tuzağa düşen bir sözleşme ihlali üretirdi ve
/// oynatmanın kendisi çalışırken bu riski almak doğru değildir.
///
/// **Durum:** `isSupported` her zaman yanlış döner, dolayısıyla arayüz PiP
/// düğmesini hiç çizmez. Kullanıcı için kayıp, oynatıcının çalışmamasından çok
/// daha küçüktür. PiP yeniden eklendiğinde bu sınıf tek yer olarak kalır ve
/// `PlayerView` içindeki `pip.toggle()` çağrısı olduğu gibi çalışır.
@MainActor
final class PictureInPictureController: ObservableObject {

    /// Cihaz PiP'i destekliyor mu?
    ///
    /// `AVPlayer` döneminde bu değer `AVPictureInPictureController.isPictureInPictureSupported()`
    /// ile belirleniyordu. Artık PiP uygulanmadığı için sabit olarak yanlış
    /// bırakılır; bu tek nokta, arayüzün düğmeyi çizip çizmemesini belirler.
    private(set) var isSupported = false

    /// PiP penceresi şu anda açık mı?
    private(set) var isActive = false

    /// Kullanıcı PiP penceresindeki "geri dön" düğmesine bastığında çağrılır.
    var onRestore: (() -> Void)?

    /// PiP'i açar/kapatır. Uygulanmadığı için hiçbir şey yapmaz.
    func toggle() {}

    /// PiP penceresini kapatır. Uygulanmadığı için hiçbir şey yapmaz.
    func stop() {}
}
