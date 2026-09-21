import AVFoundation
import Combine
import UIKit

/// `AVPlayer` tabanlı oynatma motoru.
///
/// Kapsam:
/// - HLS (`.m3u8`) canlı ve VOD akışları
/// - MP4 / MKV gibi dosya tabanlı VOD akışları (destek codec'e bağlıdır)
/// - Arka planda ses devamı ve kilit ekranı kontrolleri
/// - VOD için kaldığı yerden devam
///
/// Kapsam dışı: TS konteynerli ham akışlar. `AVPlayer` MPEG-TS'i yalnızca HLS
/// paketlemesi içinde çözebilir; bazı sağlayıcıların `/live/.../id.ts` biçimli
/// akışları oynatılamaz. Bu durumda hata kullanıcıya açıkça bildirilir
/// (bkz. `MIMARI.md` Bölüm 11 — sağlayıcı tutarsızlığı).
@MainActor
final class AVPlayerEngine: NSObject, ObservableObject, PlaybackProviding {

    // MARK: - PlaybackProviding

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentTitle: String?
    @Published private(set) var currentSubtitle: String?
    @Published private(set) var isLive: Bool = false
    @Published private(set) var duration: Double?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var didResumeFromSavedPosition: Bool = false
    @Published private(set) var isBuffering: Bool = false

    /// Oynatıcı katmanı; `VideoPlayerView` bu nesneyi kullanır.
    let player = AVPlayer()

    private var currentItem: (any MediaItem)?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var rateObservation: NSKeyValueObservation?
    private var bufferObservation: NSKeyValueObservation?
    private var savedPosition: Double = 0

    /// Konumun diske yazılma sıklığı (saniye). Her saniye yazmak gereksiz I/O olur.
    private let positionSaveInterval: Double = 10
    private var lastSavedPosition: Double = 0

    /// Kaydedilecek konumu okuyup yazan depo.
    private let recents: RecentsRepository?
    private let audioSession = AudioSessionManager.shared

    init(recents: RecentsRepository? = nil) {
        self.recents = recents
        super.init()
        configurePlayer()
        wireRemoteCommands()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        itemStatusObservation?.invalidate()
        rateObservation?.invalidate()
        bufferObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }
    }

    // MARK: - Yükleme

    func load(_ item: any MediaItem, startAt: Double? = nil) async {
        stop()

        currentItem = item
        currentTitle = item.title
        currentSubtitle = nil
        isLive = item.kind == .live
        duration = nil
        currentTime = 0
        didResumeFromSavedPosition = false
        state = .loading(item: item.title)

        audioSession.activate()

        // VOD ve dizilerde kaydedilmiş konumdan devam edilir.
        if !isLive, let saved = startAt ?? resumePosition(for: item), saved > 15 {
            savedPosition = saved
            didResumeFromSavedPosition = true
        } else {
            savedPosition = 0
        }
        lastSavedPosition = savedPosition

        // Sağlayıcıya özel başlık gereksinimleri için ortak bir UA gönderilir.
        let asset = AVURLAsset(
            url: item.streamURL,
            options: [AVURLAssetHTTPHeaderFieldsKey: ["User-Agent": "IPiOS/1.0 (iOS)"]]
        )

        let playerItem = AVPlayerItem(asset: asset)
        // Canlı yayında büyük tampon, kanal geçişini yavaşlatır; dengeli bir
        // değer seçilir. VOD'da daha agresif tampon sorunsuzdur.
        playerItem.preferredForwardBufferDuration = isLive ? 3 : 10

        observe(playerItem: playerItem)

        // İçerik oynanmaya başlamadan önce gerekli izinleri ve yayın kaydını yap.
        await recents?.record(item)

        player.replaceCurrentItem(with: playerItem)

        // Kilit ekranı bilgisi hemen gösterilir; süre geldiğinde güncellenir.
        updateNowPlaying()

        player.play()
        state = .playing(item: item.title)
    }

    // MARK: - Kontroller

    func play() {
        guard let item = currentItem else { return }
        if case .finished = state {
            seek(to: 0)
        }
        player.play()
        state = .playing(item: item.title)
        updateNowPlaying()
    }

    func pause() {
        guard let item = currentItem else { return }
        player.pause()
        state = .paused(item: item.title)
        updateNowPlaying()
        Task { await persistPosition() }
    }

    func togglePlayPause() {
        switch state {
        case .playing, .buffering:
            pause()
        default:
            play()
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeObservers()
        state = .idle
        currentTitle = nil
        currentSubtitle = nil
        currentTime = 0
        duration = nil
        isLive = false
        isBuffering = false
        didResumeFromSavedPosition = false
        currentItem = nil
    }

    func seek(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: Double) {
        guard let item = currentItem, !isLive else { return }
        let upperBound = duration.map { max($0 - 1, 0) } ?? seconds
        let target = min(max(seconds, 0), upperBound)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
        savedPosition = target
        updateNowPlaying()
    }

    func persistPosition() async {
        guard let item = currentItem, !isLive else { return }
        guard currentTime > 0 else { return }
        await recents?.savePosition(for: item, seconds: currentTime, duration: duration)
        lastSavedPosition = currentTime
    }

    func setVolume(_ value: Float) {
        player.volume = min(max(value, 0), 1)
    }

    // MARK: - Yapılandırma

    private func configurePlayer() {
        player.actionAtItemEnd = .pause
        // Uygulama arka plana geçtiğinde görüntü durur ama ses devam eder.
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
    }

    private func wireRemoteCommands() {
        audioSession.onPlay = { [weak self] in self?.play() }
        audioSession.onPause = { [weak self] in self?.pause() }
        audioSession.onToggle = { [weak self] in self?.togglePlayPause() }
        audioSession.onSkipForward = { [weak self] seconds in self?.seek(by: seconds) }
        audioSession.onSkipBackward = { [weak self] seconds in self?.seek(by: -seconds) }
    }

    // MARK: - Gözlemciler

    private func observe(playerItem: AVPlayerItem) {
        removeObservers()

        itemStatusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .failed:
                    // AVFoundation'ın verdiği metin İngilizce olabilir; bu yüzden
                    // onu doğrudan göstermek yerine yerelleştirilmiş genel bir
                    // metne eşlik eden teknik ayrıntı olarak veriyoruz.
                    let detail = item.error?.localizedDescription
                        ?? L.t("player.error.unknown")
                    self.state = .failed(
                        message: AppError.playbackFailed(reason: detail).errorDescription
                            ?? L.t("player.error.startFailed")
                    )
                case .readyToPlay:
                    if let itemDuration = item.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                        self.duration = itemDuration
                    }
                    if self.savedPosition > 0 {
                        self.player.seek(
                            to: CMTime(seconds: self.savedPosition, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                        self.currentTime = self.savedPosition
                        self.savedPosition = 0
                    }
                    self.updateNowPlaying()
                default:
                    break
                }
            }
        }

        bufferObservation = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.isBuffering = item.isPlaybackBufferEmpty
            }
        }

        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Duraklatma durumu `state` üzerinden yönetildiği için burada
                // yalnızca tampon göstergesi güncellenir.
                self.isBuffering = player.rate == 0 && self.state.isPlaying
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = .finished
                self.player.pause()
                // Biten içerik "devam et" listesinde kalmasın.
                if let item = self.currentItem {
                    await self.recents?.clearPosition(for: item)
                }
            }
        }

        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in
                self?.state = .failed(
                    message: error?.localizedDescription ?? L.t("player.error.interrupted")
                )
            }
        }

        // Zaman gözlemcisi: 0.5 sn aralıkla konum güncellenir.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                self.currentTime = seconds

                if let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }

                // VOD'da konum periyodik olarak diske yazılır.
                if !self.isLive,
                   abs(seconds - self.lastSavedPosition) >= self.positionSaveInterval {
                    await self.persistPosition()
                }
            }
        }
    }

    private func removeObservers() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            self.failedObserver = nil
        }
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        rateObservation?.invalidate()
        rateObservation = nil
        bufferObservation?.invalidate()
        bufferObservation = nil
    }

    // MARK: - Yardımcılar

    private func resumePosition(for item: any MediaItem) -> Double? {
        recents?.position(for: item)?.seconds
    }

    private func updateNowPlaying() {
        audioSession.updateNowPlaying(
            title: currentTitle,
            subtitle: currentSubtitle,
            isLive: isLive,
            duration: duration,
            elapsed: currentTime,
            artworkURL: currentItem?.imageURL
        )
    }
}

// MARK: - Durum yardımcıları

extension PlaybackState {
    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Oynatıcının meşgul olduğu (yükleme / tampon) durumlar.
    var isLoading: Bool {
        switch self {
        case .loading, .buffering: return true
        default: return false
        }
    }
}
