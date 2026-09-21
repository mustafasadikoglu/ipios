import Foundation

/// Oynatıcı durumu.
enum PlaybackState: Equatable, Sendable {
    case idle
    case loading(item: String)
    case playing(item: String)
    case paused(item: String)
    case buffering
    case failed(message: String)
    case finished
}

/// Oynatma motoru arayüzü.
///
/// Somut implementasyon `AVPlayerEngine`. Arayüz ayrı tutulur ki ileride
/// VLCKit tabanlı bir motor (örneğin TS akışlarında daha geniş codec desteği
/// için) aynı ekranları bozmadan eklenebilsin.
@MainActor
protocol PlaybackProviding: AnyObject {

    /// Anlık durum.
    var state: PlaybackState { get }

    /// Oynatılan öğenin başlığı.
    var currentTitle: String? { get }

    /// Canlı yayın mı? (İlerleme çubuğu ve "CANLI" etiketi buna göre gösterilir.)
    var isLive: Bool { get }

    /// İçeriğin süresi; canlı yayında sonsuz/`nil` olabilir.
    var duration: Double? { get }

    /// Anlık konum (saniye).
    var currentTime: Double { get }

    /// Kaydedilmiş izleme konumundan devam edilip edilmediği.
    var didResumeFromSavedPosition: Bool { get }

    /// Oynatmayı başlatır.
    /// - Parameter startAt: VOD/dizi için başlangıç saniyesi.
    func load(_ item: MediaItem, startAt: Double?) async

    func play()
    func pause()
    func togglePlayPause()
    func stop()

    /// Saniye cinsinden atlama (negatif = geri).
    func seek(by seconds: Double)
    func seek(to seconds: Double)

    /// Oynatma konumunu kalıcı hale getirir (uygulama arka plana geçerken).
    func persistPosition() async

    /// Ses seviyesi 0...1.
    func setVolume(_ value: Float)
}
