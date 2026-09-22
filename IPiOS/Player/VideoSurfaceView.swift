import SwiftUI
import UIKit

/// libvlc görüntüsünü SwiftUI içinde gösteren katman.
///
/// **Bu görünüm artık yüzeyi üretmez, yalnızca barındırır.** Yüzeyin sahibi
/// motordur (`VLCPlayerEngine.videoSurface`) ve oynatıcı kurulurken bir kez
/// oluşturulup `drawable` olarak atanır. Bu ayrım bir kusurun düzeltmesidir;
/// gerekçesi aşağıda.
///
/// **Ölçülmüş kusur (ses var, görüntü yok):** yüzey eskiden burada,
/// `makeUIView` içinde üretilip `player.drawable`'a bağlanıyordu ve
/// `willMove(toWindow: nil)` ile görünüm ekrandan çıktığında bağ **koparılıyordu**
/// (`player.drawable = nil`). Oysa oynatma `PlayerPresenter.present()` içinde,
/// kapak görünümü daha çizilmeden başlatılır. Yani libvlc görüntü çıkışını
/// kurarken `drawable` çoğu zaman **henüz atanmamış** oluyordu. Sonuç: ses
/// çıkışı kurulur, görüntü çıkışı kurulamaz — kullanıcı sesi duyar, ekran
/// siyah kalır. Bir yarış olduğu için belirti kararsızdı: ağ yavaş açılan
/// dosyalarda yüzey yetişiyor, hızlı açılanlarda yetişmiyordu. Aynı yarış
/// kapak kapanıp açıldığında ve döndürme sırasında da tekrarlanıyordu.
///
/// Kalıcı yüzey bu yarışı tümüyle ortadan kaldırır: bağ, oynatma başlamadan
/// **çok önce** kurulmuş olur ve hiçbir zaman koparılmaz.
struct VideoSurfaceView: UIViewRepresentable {

    /// Motorun sahibi olduğu kalıcı görüntü yüzeyi.
    let surface: UIView

    func makeUIView(context: Context) -> SurfaceHostView {
        let host = SurfaceHostView()
        host.backgroundColor = .black
        host.host(surface)
        return host
    }

    func updateUIView(_ uiView: SurfaceHostView, context: Context) {
        uiView.host(surface)
    }
}

/// Motorun yüzeyini kendi sınırlarına yerleştiren, sade bir kabuk.
///
/// Yüzeyin kendisi **motorun malıdır** ve bu görünüm onu yalnızca barındırır.
/// Böylece oynatıcı ekranı kapansa bile `drawable` bağı kopmaz; sesin devam
/// ettiği ama görüntünün kaybolduğu durum oluşamaz.
final class SurfaceHostView: UIView {

    private weak var hosted: UIView?

    /// Yüzeyi kabuğa yerleştirir. Zaten yerleştirilmişse hiçbir şey yapmaz.
    func host(_ surface: UIView) {
        guard hosted !== surface else { return }

        hosted?.removeFromSuperview()
        surface.removeFromSuperview()
        surface.frame = bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(surface)
        hosted = surface
    }
}
