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
/// Canlı yayında yedek adres: `AVPlayer` ham MPEG-TS konteynerini çözemez,
/// yalnızca HLS paketlemesi içindeki TS parçalarını oynatabilir. Sağlayıcılar
/// aynı yayını hem `.m3u8` hem `.ts` yolundan sunabildiği ve hangisinin doğru
/// olduğu önceden bilinemediği için canlı içerikte sırayla birden çok adres
/// denenir (bkz. `playbackCandidates(for:)`). Hiçbiri açılmazsa hata kullanıcıya
/// açıkça bildirilir (`MIMARI.md` Bölüm 11 — sağlayıcı tutarsızlığı).
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

    /// Son hata, `AVPlayer`'ın çözemeyeceği bir yayın biçiminden mi kaynaklandı?
    ///
    /// Arayüz bunu ayrı bir uyarı metniyle gösterir. Bayrak olarak tutulur
    /// çünkü `PlaybackState.failed` yalnızca bir metin taşır ve metin
    /// karşılaştırması yerelleştirmeye bağlı olarak kırılgan olurdu.
    var lastFailureWasUnsupportedFormat: Bool {
        if case .failed = state { return didFailOnUnsupportedFormat }
        return false
    }
    private var didFailOnUnsupportedFormat = false

    /// Son başarısız `AVPlayerItem` denemesinin kullanıcıya gösterilebilir
    /// metni.
    ///
    /// Denemeler arasında **yayınlanmaz**: birden çok adres sırayla
    /// denendiğinde ara hataların kullanıcıya gösterilmesi, oynatma nihayetinde
    /// başlasa bile ekranda bir hata uyarısı bırakırdı. Yalnızca tüm adaylar
    /// tükendiğinde `state`'e taşınır.
    private var lastAttemptFailureMessage: String?

    /// Oynatıcı katmanı; `VideoPlayerView` bu nesneyi kullanır.
    let player = AVPlayer()

    /// `AVURLAsset` seçenekleri anahtarı.
    ///
    /// `AVURLAssetHTTPHeaderFieldsKey` Objective-C sabiti Swift'e
    /// köprülenmediği için değeri burada tutulur; sihirli dize tek yerde kalır.
    private static let headerFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"

    private var currentItem: (any MediaItem)?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var rateObservation: NSKeyValueObservation?
    private var bufferObservation: NSKeyValueObservation?
    private var savedPosition: Double = 0

    /// Başlatmanın sonucu; `AVPlayerItem` hazır ya da başarısız olduğunda yazılır.
    private enum StartupOutcome { case ready, failed }

    /// Başlatma bekleyicisi: `AVPlayerItem` hazır ya da başarısız olduğunda
    /// (veya süre aşıldığında) bir kez tetiklenir.
    ///
    /// Neden gerekli: `load` çağrısı döndükten sonra sonucun ne olduğunu
    /// bilmek, yedek adrese geçmek ve hatayı kullanıcıya bildirmek için
    /// `AVPlayerItem`'ın durumunu beklemek zorundayız.
    ///
    /// Sonuç ayrıca bir bayrakta tutulur (`startupOutcome`): durum gözlemcisi
    /// `Task { @MainActor }` ile ana aktöre atladığı için, bekleyici kurulmadan
    /// önce sonuç üretilmiş olabilir. Bayrak bu yarışı kapatır — aksi halde
    /// bekleyici hiç serbest bırakılmaz ve oynatıcı süre aşımına kadar asılı
    /// kalırdı.
    private var startupOutcome: StartupOutcome?
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?

    /// Başlatma için beklenecek azami süre (saniye). Canlı yayında kanal
    /// geçişi hızlı olmalı; VOD'da sunucu daha yavaş yanıt verebilir.
    private var startupTimeout: Double { isLive ? 12 : 20 }

    /// Sırayla denenen adresler. İlk eleman öğenin kendi adresidir.
    private var candidateURLs: [URL] = []
    private var candidateIndex = 0

    /// Yükleme nesli. Kullanıcı bir yayın yüklenirken başka bir kanala
    /// geçtiğinde eski deneme döngüsü hâlâ askıda olabilir; bu sayaç sayesinde
    /// eskimiş döngü durumu ezmez (bkz. `attemptPlayback(generation:)`).
    private var attemptGeneration = 0

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

        // İçerik oynanmaya başlamadan önce gerekli izinleri ve yayın kaydını yap.
        await recents?.record(item)

        candidateURLs = Self.playbackCandidates(for: item, isLive: isLive)
        candidateIndex = 0

        attemptGeneration += 1
        await attemptPlayback(generation: attemptGeneration)
    }

    // MARK: - Adres denemeleri

    /// Adayları sırayla dener; ilk açılan adres oynatılır.
    ///
    /// Bir adres `AVPlayerItem` düzeyinde açılamazsa (örneğin `.ts` konteyneri
    /// çözülemediğinde) sonraki aday denenir. Hiçbiri açılmazsa son hata durumu
    /// kullanıcıya bırakılır.
    ///
    /// - Parameter generation: Bu döngünün ait olduğu yükleme nesli. Bekleme
    ///   sırasında yeni bir yükleme başlarsa nesil değişir ve döngü hiçbir
    ///   durum yazmadan çekilir. Böylece eski bir denemenin hatası, yeni
    ///   yayının durumunu ezemez.
    private func attemptPlayback(generation: Int) async {
        while candidateIndex < candidateURLs.count {
            guard generation == attemptGeneration else { return }

            let url = candidateURLs[candidateIndex]
            // Yalnızca uzantı yazılır: adresin tamamı sağlayıcı hesabına ait
            // bilgiler taşır ve günlükte gereksizdir.
            Log.player.debug(
                "Oynatma denemesi \(self.candidateIndex + 1)/\(self.candidateURLs.count), uzantı: \(url.pathExtension, privacy: .public)"
            )

            startItem(with: url)
            await waitForReadyOrFailure()

            // Bekleme bitiminde yeni bir yükleme başlamış olabilir; bu durumda
            // bu döngü tamamen ilgisizdir.
            guard generation == attemptGeneration else { return }

            guard startupOutcome == .ready else {
                // Bu adres açılmadı; sıradaki varsa denenir.
                candidateIndex += 1
                continue
            }

            // `AVPlayerItem` hazır: oynatma gerçekten başlatılır.
            player.play()
            state = .playing(item: currentItem?.title ?? "")
            updateNowPlaying()
            return
        }

        // Döngü hiç çalışmadan buraya düşülebilir: `stop()` aday listesini
        // boşaltıp nesli ilerletir, uçuşta kalan eski döngü ise koşulu
        // sağlamadan kuyruğa ulaşır. Bu durumda hata yazmak, `stop()`'un
        // bıraktığı `.idle` durumunu ezer ve kapatılmış bir oynatıcıda hata
        // uyarısı açardı.
        guard generation == attemptGeneration, !candidateURLs.isEmpty else { return }

        // Tüm adaylar tükendi; artık nihai hata yazılabilir.
        //
        // Özel durum: kaynağın kendi sunduğu adres ham MPEG-TS ise bunu açıkça
        // söyleriz. Kullanıcı "neden oynamıyor?" sorusunun cevabını görsün ve
        // aynı sorunu tekrar bildirmek zorunda kalmasın.
        //
        // Ölçüt, son denenen adres değil **asıl** adrestir: yedek olarak
        // türettiğimiz `.ts` adresi son sırada denendiği için, sona bakmak
        // HLS adresi de başarısız olduğunda teşhisi yanlış yere yazardı.
        let primaryIsRawTransportStream =
            currentItem?.streamURL.pathExtension.lowercased() == "ts"

        let message: String
        if primaryIsRawTransportStream {
            message = L.t("player.error.tsUnsupported")
        } else {
            message = lastAttemptFailureMessage ?? L.t("player.error.startFailed")
        }

        // Bayrak **durumdan önce** yazılır: durum aboneliği (`Combine`) atama
        // anında eşzamanlı çalışır ve arayüz bayrağı o sırada okur.
        didFailOnUnsupportedFormat = primaryIsRawTransportStream
        state = .failed(message: message)
    }

    /// Tek bir adres için `AVPlayerItem` kurar ve gözlemcileri bağlar.
    private func startItem(with url: URL) {
        removeObservers()
        startupOutcome = nil
        // Her adres kendi hatasını taşır; önceki denemenin mesajı sızmamalı.
        lastAttemptFailureMessage = nil

        // Sağlayıcıya özel başlık gereksinimleri için ortak bir UA gönderilir.
        //
        // `AVURLAssetHTTPHeaderFieldsKey` Swift'e köprülenmemiş bir
        // Objective-C sabitidir; anahtar bu yüzden dize olarak verilir.
        let asset = AVURLAsset(
            url: url,
            options: [Self.headerFieldsKey: ["User-Agent": "IPiOS/1.0 (iOS)"]]
        )

        let playerItem = AVPlayerItem(asset: asset)
        // Canlı yayında büyük tampon, kanal geçişini yavaşlatır; dengeli bir
        // değer seçilir. VOD'da daha agresif tampon sorunsuzdur.
        playerItem.preferredForwardBufferDuration = isLive ? 3 : 10

        observe(playerItem: playerItem)
        player.replaceCurrentItem(with: playerItem)
    }

    /// `AVPlayerItem` hazır ya da başarısız olana kadar bekler; süre aşılırsa
    /// denemeyi başarısız sayar.
    ///
    /// Süre aşımı gerçek bir hatadır: adres yanıt vermiyor demektir. Ancak bu
    /// da bir **ara** sonuçtur; yedek adres varsa sıradaki denenir ve kullanıcı
    /// yalnızca hepsi başarısız olursa bilgilendirilir (bkz. `attemptPlayback`).
    private func waitForReadyOrFailure() async {
        // Sonuç bekleyici kurulmadan önce üretilmiş olabilir; bu durumda
        // beklemeden dönülür.
        if startupOutcome != nil { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            readyContinuation = continuation
            startupTimeoutTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.startupTimeout))
                guard !Task.isCancelled else { return }
                self.handleStartupTimeout()
            }
        }
    }

    private func handleStartupTimeout() {
        // Gözlemci bu adres için zaten bir hata metni yazdıysa o metin korunur;
        // daha açıklayıcı olan sağlayıcı/motor hatasıdır.
        if lastAttemptFailureMessage == nil {
            lastAttemptFailureMessage = L.t("player.error.timeout")
        }
        signalReady(.failed)
    }

    /// Bekleyeni (varsa) tek kez serbest bırakır ve sonucu kaydeder.
    ///
    /// İkinci çağrı yok sayılır; böylece `.readyToPlay` sonrası gelen geç bir
    /// hata bildirimi yedek adrese gereksiz geçişe yol açmaz.
    private func signalReady(_ outcome: StartupOutcome) {
        guard startupOutcome == nil else { return }
        startupOutcome = outcome

        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil

        guard let continuation = readyContinuation else { return }
        readyContinuation = nil
        continuation.resume()
    }

    // MARK: - Kontroller

    func play() {
        guard let item = currentItem else { return }
        // Yükleme başarısızsa oynatma başlatılamaz; durum olduğu gibi kalır ki
        // hata mesajı kaybolmasın.
        guard !state.isFailed else { return }

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
        // Bekleyen bir başlatma varsa serbest bırakılır; aksi halde `load`
        // sonsuza kadar askıda kalırdı. Sonuç `.failed` yazılır ki deneme
        // döngüsü yeni bir adrese geçmeye çalışmasın.
        signalReady(.failed)
        startupOutcome = nil
        candidateURLs = []
        candidateIndex = 0
        // Nesil ilerletilir: uçuşta kalan döngüler bundan sonra durum yazamaz.
        attemptGeneration += 1
        state = .idle
        currentTitle = nil
        currentSubtitle = nil
        currentTime = 0
        duration = nil
        isLive = false
        isBuffering = false
        didResumeFromSavedPosition = false
        didFailOnUnsupportedFormat = false
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
                // Ana aktöre atlarken gecikme olabilir; bu arada başka bir
                // adres/öğe devreye girmişse bu bildirim ilgisizdir.
                guard self.player.currentItem === item else { return }
                switch item.status {
                case .failed:
                    // AVFoundation'ın verdiği metin İngilizce olabilir; bu yüzden
                    // onu doğrudan göstermek yerine yerelleştirilmiş genel bir
                    // metne eşlik eden teknik ayrıntı olarak veriyoruz.
                    let detail = item.error?.localizedDescription
                        ?? L.t("player.error.unknown")
                    self.lastAttemptFailureMessage =
                        AppError.playbackFailed(reason: detail).errorDescription
                            ?? L.t("player.error.startFailed")
                    // Hata burada **yayınlanmaz**: yedek bir adres varsa sıradaki
                    // deneme başarılı olabilir. Nihai durum `attemptPlayback`
                    // tarafından yazılır.
                    self.signalReady(.failed)
                case .readyToPlay:
                    // `duration.seconds` isteğe bağlı değil; yalnızca geçerli ve
                    // sonlu bir değer olduğunda kullanılır (canlıda `nan` gelir).
                    let itemDuration = item.duration.seconds
                    if itemDuration.isFinite, itemDuration > 0 {
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
                    // Öğe çözülebildi: ilk kare görünmeye hazır.
                    self.signalReady(.ready)
                default:
                    break
                }
            }
        }

        bufferObservation = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Eski öğeden gelen gecikmiş bildirim, yeni adresin tampon
                // göstergesini yanlışlıkla açık bırakırdı.
                guard self.player.currentItem === item else { return }
                self.isBuffering = item.isPlaybackBufferEmpty
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

        // Oynatma **başladıktan sonra** kesilme. Ara bir deneme hatası değildir:
        // yedek adres denemek anlamsız olurdu (yayın zaten açılmıştı), bu
        // yüzden durum doğrudan yazılır.
        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in
                guard let self else { return }
                // `AVFoundation` metni İngilizce olabilir; teknik ayrıntı
                // yerelleştirilmiş genel mesaja eşlik eder.
                let detail = error?.localizedDescription ?? L.t("player.error.unknown")
                self.state = .failed(
                    message: AppError.playbackFailed(reason: detail).errorDescription
                        ?? L.t("player.error.interrupted")
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
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            // `removeTimeObserver` tekrar çağrılmaması için kayıt temizlenir;
            // bu yüzden değişken `let` değil `var` olmalı.
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

    /// Denerken kullanılacak adres listesini üretir.
    ///
    /// Canlı yayında sağlayıcılar aynı kanalı iki farklı biçimde sunabilir:
    /// `/live/<user>/<pass>/<id>.m3u8` (HLS) veya `/live/<user>/<pass>/<id>.ts`
    /// (ham MPEG-TS). `AVPlayer` yalnızca ilkini oynatabildiği için önce HLS
    /// denenir; sağlayıcı HLS sunmuyorsa ham TS'e düşülür ve oynatıcı hata
    /// verirse durum kullanıcıya bildirilir.
    ///
    /// VOD ve dizilerde uzantı sağlayıcının bildirdiği konteynerdir. `AVPlayer`
    /// bunların hepsini çözemez (`.mkv`, `.avi`, `.webm` desteklenmez); bu
    /// yüzden tek adayla yetinmek yerine uzantının **okunabilir** olup
    /// olmadığına bakılır: çözülemeyen ve HLS'e çevrilebilir bir konteyner
    /// (`.mkv` gibi) için `.m3u8` yedeği eklenir. Sağlayıcı aynı içeriği HLS
    /// olarak sunuyorsa oynatma yine de başlar; sunmuyorsa hata açıkça
    /// bildirilir.
    static func playbackCandidates(for item: any MediaItem, isLive: Bool) -> [URL] {
        let primary = item.streamURL

        if isLive {
            let ts = replacingExtension(of: primary, with: "ts")
            let m3u8 = replacingExtension(of: primary, with: "m3u8")

            var candidates: [URL] = []
            for url in [m3u8, ts] where url != nil {
                if !candidates.contains(url!) { candidates.append(url!) }
            }
            // Uzantı tanınmadıysa (örneğin uzantısız adres) asıl adres korunur.
            if candidates.isEmpty { candidates = [primary] }
            return candidates
        }

        // VOD: yalnızca `AVPlayer`'ın çözemediği konteynerler için yedek üretilir.
        //
        // Yedek olarak **HLS değil `mp4`** denenir. Xtream VOD içeriğini HLS
        // paketlemesiyle sunmaz; `/movie/<user>/<pass>/<id>.m3u8` diye bir yol
        // yoktur. Buna karşılık tek bir konteyner uzantısı bildirip dosyayı
        // farklı uzantıyla sunan paneller yaygındır — `container_extension`
        // "mkv" derken adresin `.mp4` olarak da çalıştığı sık görülür. Bu
        // yüzden yedek, oynatılabilir tek biçim olan `.mp4`'tür.
        let ext = primary.pathExtension.lowercased()
        guard Self.unplayableContainers.contains(ext) else { return [primary] }

        guard let mp4 = replacingExtension(of: primary, with: "mp4") else {
            return [primary]
        }
        return [primary, mp4]
    }

    /// `AVPlayer`'ın doğrudan çözemediği video konteynerleri.
    ///
    /// Bu uzantılarda oynatma neredeyse her zaman başarısız olur; yedek adres
    /// denemesi bu yüzden anlamlıdır. `.mp4`, `.mov` ve `.m2ts` listede
    /// değildir — onlar zaten oynatılabilir ve gereksiz bir deneme, sağlayıcıya
    /// boşuna istek göndermek olurdu.
    private static let unplayableContainers: Set<String> = ["mkv", "avi", "webm", "flv", "wmv"]

    /// Adresin yol uzantısını değiştirir. Uzantı yoksa `nil` döner; böylece
    /// anlamsız bir adres üretilmez.
    private static func replacingExtension(of url: URL, with newExtension: String) -> URL? {
        guard !url.pathExtension.isEmpty else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = url.path
        let base = path.hasSuffix(".\(url.pathExtension)")
            ? String(path.dropLast(url.pathExtension.count + 1))
            : path
        components?.path = "\(base).\(newExtension)"
        return components?.url
    }

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
