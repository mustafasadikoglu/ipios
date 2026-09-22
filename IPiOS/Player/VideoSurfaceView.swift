import SwiftUI
import UIKit
import VLCKit

/// libvlc görüntüsünü SwiftUI içinde gösteren katman.
///
/// `AVPlayer` döneminde bu görünüm `AVPlayerLayer`'ı barındırıyordu ve katman
/// tipi `layerClass` ile sabitlenmek zorundaydı. libvlc'de böyle bir zorunluluk
/// yok: `VLCMediaPlayer.drawable` **herhangi bir `UIView`** kabul eder ve kendi
/// görüntü alt katmanını o görünüme ekler. Bu yüzden sade bir `UIView` yeterli
/// ve en düşük riskli seçenektir — `VLCDrawable` protokolünün istediği iki üye
/// (`addSubview:` ve `bounds`) `UIView`'da zaten vardır.
///
/// Ölçekleme burada **değil** oynatıcıda ayarlanır (`videoFitMode`), çünkü
/// libvlc görüntüyü kendi çizdiği alt katmana yerleştirir ve SwiftUI tarafından
/// yapılan hiçbir katman ayarı onu etkilemez.
struct VideoSurfaceView: UIViewRepresentable {

    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.backgroundColor = .black
        view.attach(to: player)
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        uiView.attach(to: player)
    }
}

/// Oynatıcının görüntüsünü barındıran ve `drawable` bağını **iki yönlü**
/// yöneten görünüm.
///
/// İki yönlü yönetim neden gerekli: `VLCMediaPlayer.drawable` kuvvetli
/// (strong) tutulur. Yalnızca bağlamak yetmez — görünüm ekrandan çıktığında
/// bırakılmazsa kapandığı sanılan oynatıcı ekranının görünümü bellekte asılı
/// kalır ve bir sonraki açılışta iki yüzey birden oynatıcıya bağlı kalabilir.
final class PlayerSurfaceView: UIView {

    /// Zayıf tutulur: oynatıcı zaten motor tarafından güçlü tutulur ve
    /// oynatıcı bu görünümü güçlü tuttuğu için burada güçlü bir referans
    /// döngü oluştururdu.
    private weak var player: VLCMediaPlayer?

    /// Oynatıcıya bağlanır (gerekmiyorsa hiçbir şey yapmaz).
    func attach(to player: VLCMediaPlayer) {
        self.player = player
        guard player.drawable as? UIView !== self else { return }
        player.drawable = self
    }

    /// Görünüm pencere hiyerarşisine girdiğinde/çıktığında bağı günceller.
    ///
    /// Bu kanca `dismantleUIView` yerine tercih edildi: `dismantleUIView`
    /// statik olduğu için oynatıcı örneğine erişemez ve bağ yalnızca SwiftUI'ın
    /// görünümü tamamen sökmesiyle koparılırdı. `willMove(toWindow:)` ise
    /// görünüm ekrandan çıktığı anda çalışır ve **kendini onarır**: pencere
    /// yeniden atandığında bağ geri kurulur, böylece geçici bir sökülme
    /// oynatmayı kalıcı olarak karartmaz.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        guard let player else { return }

        if newWindow == nil {
            if player.drawable as? UIView === self {
                player.drawable = nil
            }
        } else if player.drawable as? UIView !== self {
            player.drawable = self
        }
    }
}
