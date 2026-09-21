import AVFoundation
import SwiftUI

/// `AVPlayer` görüntüsünü SwiftUI içinde gösteren katman.
///
/// `AVPlayerViewController` yerine `AVPlayerLayer` kullanılır: kendi kontrol
/// arayüzümüzü çizdiğimiz için sistem kontrollerine ihtiyaç yoktur ve bu yol
/// daha az davranış sürprizi üretir.
struct VideoSurfaceView: UIViewRepresentable {

    let player: AVPlayer

    /// Görüntünün en-boy oranına göre ölçeklenip ölçeklenmeyeceği.
    /// Canlı yayınlarda tam ekran doldurma, VOD'da oranı koruma tercih edilir.
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    /// Katman oluşturulduğunda (ve gerektiğinde yeniden) bildirilir.
    ///
    /// Neden gerekli: küçük pencere (PiP) denetimi yalnızca somut bir
    /// `AVPlayerLayer` üzerine kurulabilir; SwiftUI görünümü dışarıya katman
    /// vermez, bu yüzden katman hazır olduğunda buradan iletilir. Aynı zamanda
    /// katman sahipliği oynatıcıdan alınmış olur.
    var onLayerReady: ((AVPlayerLayer) -> Void)?

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        onLayerReady?(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = videoGravity
    }
}

/// `AVPlayerLayer`'ı barındıran ve katman sınıfını `AVPlayerLayer` olarak
/// bildiren görünüm. Katman tipi `layerClass` ile sabitlenmezse katman
/// boyutlandırma sırasında yanlış ölçeklenir.
final class PlayerLayerView: UIView {

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // `layerClass` gereği bu dönüşüm her zaman geçerlidir.
        layer as! AVPlayerLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
