import AVFoundation
import MediaPlayer
import UIKit

/// Uygulama genelinde ses oturumunu ve kilit ekranı kontrollerini yönetir.
///
/// Ses kategorisi `.playback` seçilir; bu sayede ekran kilitlense veya uygulama
/// arka plana geçse bile yayın sesi devam eder (`UIBackgroundModes: audio` ile
/// birlikte çalışır).
@MainActor
final class AudioSessionManager {

    static let shared = AudioSessionManager()

    private var isConfigured = false
    private let remoteCommands = MPRemoteCommandCenter.shared()

    /// Oynatıcının kilit ekranı kontrollerine bağlanacağı kapanışlar.
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onToggle: (() -> Void)?
    var onSkipForward: ((Double) -> Void)?
    var onSkipBackward: ((Double) -> Void)?

    private init() {}

    // MARK: - Oturum

    /// Oturumu oynatma için hazırlar. Zaten hazırsa tekrar yapılandırmaz.
    func activate() {
        guard !isConfigured else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
            isConfigured = true
            registerRemoteCommands()
        } catch {
            Log.player.error("Ses oturumu ayarlanamadi: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Oynatma tamamen bittiğinde oturumu serbest bırakır.
    ///
    /// Bu çağrı yapılmazsa arka plandaki diğer uygulamaların sesi cihazda
    /// kısılmış kalabilir.
    func deactivate() {
        guard isConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            Log.player.debug("Ses oturumu kapatilamadi: \(error.localizedDescription, privacy: .public)")
        }
        isConfigured = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Kilit ekranı

    private func registerRemoteCommands() {
        remoteCommands.playCommand.isEnabled = true
        remoteCommands.pauseCommand.isEnabled = true
        remoteCommands.togglePlayPauseCommand.isEnabled = true
        remoteCommands.skipForwardCommand.isEnabled = true
        remoteCommands.skipBackwardCommand.isEnabled = true
        remoteCommands.skipForwardCommand.preferredIntervals = [15]
        remoteCommands.skipBackwardCommand.preferredIntervals = [15]

        remoteCommands.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        remoteCommands.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }
        remoteCommands.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onToggle?()
            return .success
        }
        remoteCommands.skipForwardCommand.addTarget { [weak self] _ in
            self?.onSkipForward?(15)
            return .success
        }
        remoteCommands.skipBackwardCommand.addTarget { [weak self] _ in
            self?.onSkipBackward?(15)
            return .success
        }
    }

    /// Kilit ekranı / kontrol merkezi bilgilerini günceller.
    ///
    /// - Parameters:
    ///   - title: İçerik başlığı.
    ///   - subtitle: Kanal adı veya dizi adı.
    ///   - isLive: Canlı yayın mı? Canlıda süre çubuğu gösterilmez.
    ///   - duration: Toplam süre (saniye).
    ///   - elapsed: Anlık konum (saniye).
    ///   - artworkURL: Kapak görseli adresi.
    func updateNowPlaying(
        title: String?,
        subtitle: String?,
        isLive: Bool,
        duration: Double?,
        elapsed: Double,
        artworkURL: URL?
    ) {
        guard let title else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: isLive
        ]
        if let subtitle { info[MPMediaItemPropertyArtist] = subtitle }
        if let duration, duration > 0, !isLive {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Kapak görseli ağdan indirilir; hata olsa da oynatma etkilenmez.
        guard let artworkURL else { return }
        Task {
            guard let data = try? await URLSession.shared.data(from: artworkURL).0,
                  let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            updated[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }
}
