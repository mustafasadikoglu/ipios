import AVFoundation
import Combine
import UIKit

/// `AVPlayer` tabanlı oynatma motoru.
///
/// Kapsam:
/// - HLS (`.m3u8`) canlı ve VOD akışları
/// - Dosya tabanlı VOD akışları — **yalnızca `AVPlayer`'ın çözebildiği
///   konteyner ve kodeklerde**: MKV/AVI/WebM konteynerleri, AC3/E-AC3/DTS/Opus
///   sesleri ve AV1/VP9 görüntüleri desteklenmez. Desteklenmeyen bir **ses**
///   kodeği, görüntü kodeği destekli olsa bile öğenin tamamını düşürür.
/// - Arka planda ses devamı ve kilit ekranı kontrolleri
/// - VOD için kaldığı yerden devam
///
/// Aday listesi tükendiğinde kullanıcıya gösterilen metin tahminle değil
/// **ölçümle** üretilir: akışın taşıdığı kodekler okunur ve hata zinciri
/// çözümlenir (bkz. `PlaybackDiagnostics`). Neden gerekli: "Oynatma
/// başlatılamadı." cümlesi üç ayrı kusuru (desteklenmeyen kodek, tanınmayan
/// konteyner, sunucu reddi) aynı metne indiriyordu ve sorun teşhis edilemiyordu.
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

    /// Son başarısız `AVPlayerItem` denemesinin ham hatası.
    ///
    /// Denemeler arasında **yayınlanmaz**: birden çok adres sırayla
    /// denendiğinde ara hataların kullanıcıya gösterilmesi, oynatma nihayetinde
    /// başlasa bile ekranda bir hata uyarısı bırakırdı. Yalnızca tüm adaylar
    /// tükendiğinde sınıflandırılıp `state`'e taşınır.
    ///
    /// Neden ham hata saklanır: kullanıcıya gösterilecek metni burada üretmek,
    /// gerçek nedeni (kodek mi, konteyner mi, sunucu reddi mi) bilmeden tahmin
    /// yürütmek olurdu. Sınıflandırma tek yerde ve tüm denemeler bittikten
    /// sonra yapılır (bkz. `PlaybackDiagnostics.classify`).
    private var lastAttemptError: Error?

    /// Son başarısız denemenin adresi.
    ///
    /// Ölçüm bu adres üzerinden yapılır: hata hangi adresten geldiyse kodek de
    /// oradan okunmalıdır. Yedek adres denendiğinde değer güncellenir; böylece
    /// "asıl adres başarısız, mp4 yedeği başarısız" durumunda ölçüm **son**
    /// adresi yansıtır ve yanlış teşhis yazılmaz.
    private var lastFailedURL: URL?

    /// Son denemenin akış ölçümü yapılmış adresi.
    ///
    /// Ölçüm pahalıdır (ağ); aynı akış için bir kez yapılır. Adres
    /// değiştiğinde önceki ölçüm geçersizdir ve yeniden ölçülür.
    private var lastInspectedURL: URL?
    private var lastInspection: StreamInspection?

    /// Son deneme süre aşımına mı uğradı?
    ///
    /// Ayrı bayrak: süre aşımı hatasız gelir (`AVPlayerItem` hata üretmez),
    /// dolayısıyla hatadan ayırt edilemez.
    private var lastAttemptTimedOut = false

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
                // Bu adres açılmadı. Hatanın hangi adresten geldiği saklanır:
                // teşhis ölçümü bu adres üzerinden yapılır.
                lastFailedURL = url
                // Sıradaki varsa denenir.
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

        // Neden ölçüm: "Oynatma başlatılamadı." metni kullanıcıya hiçbir şey
        // söylemiyordu ve sorun üç turdur teşhis edilemiyordu. Gerçek neden
        // çoğu zaman taşıyıcıda ya da kodektedir (ör. H.264 görüntü + AC3 ses
        // → AVPlayer ses kodekini çözemez ve öğenin **tamamı** düşer). Bu
        // yüzden hata metni tahminle değil, akışın kendisi okunarak üretilir.
        //
        // Ölçüm yalnızca gerektiğinde ve **bir kez** yapılır; her başarısız
        // denemede ağa çıkılmaz.
        // Ölçümden önce oynatıcı bırakılır.
        //
        // İki nedeni var: (1) başarısız öğe hâlâ sunucu bağlantısını tutuyor
        // olabilir ve Xtream panelleri eşzamanlı bağlantıyı sınırlar — ikinci
        // bir bağlantı açmak ölçümü yanıltırdı; (2) `AVFoundation` aynı adres
        // için başarısız sonucu önbelleğe alabilir ve ölçüm gerçek dosyaya
        // bakmadan "okunamadı" derdi.
        player.replaceCurrentItem(with: nil)
        removeObservers()

        var inspection = lastInspection
        if let failedURL = lastFailedURL, lastInspectedURL != failedURL {
            inspection = await PlaybackDiagnostics.inspect(failedURL)
            lastInspection = inspection
            lastInspectedURL = failedURL
        }

        // Ölçüm `await` içerir; bu sırada kullanıcı başka bir yayına geçmiş ya
        // da oynatıcı kapatılmış olabilir. Durum yazılmadan önce nesil yeniden
        // doğrulanır — aksi hâlde kapatılmış bir oynatıcıda sahte hata açılırdı.
        guard generation == attemptGeneration else { return }

        let failure = PlaybackDiagnostics.classify(
            error: lastAttemptError,
            timedOut: lastAttemptTimedOut,
            inspection: isLive ? nil : inspection,
            extensionHint: currentItem?.streamURL.pathExtension.lowercased() ?? ""
        )

        // Teşhis günlüğe yazılır: kullanıcı yalnızca ekrandaki metni görür ama
        // sorun tekrar bildirildiğinde hangi adresin/adedin denendiği burada
        // kayıtlıdır. Adresin tamamı **yazılmaz** (sağlayıcı hesabı taşır).
        Log.player.error(
            "Oynatma başarısız: \(failure.technicalCode, privacy: .public) — denenen adres sayısı: \(self.candidateURLs.count)"
        )

        let message = primaryIsRawTransportStream
            ? L.t("player.error.tsUnsupported")
            : failure.fullMessage

        // Bayrak **durumdan önce** yazılır: durum aboneliği (`Combine`) atama
        // anında eşzamanlı çalışır ve arayüz bayrağı o sırada okur.
        didFailOnUnsupportedFormat = primaryIsRawTransportStream
        state = .failed(message: message)
    }

    /// Tek bir adres için `AVPlayerItem` kurar ve gözlemcileri bağlar.
    private func startItem(with url: URL) {
        removeObservers()
        startupOutcome = nil
        // Her adres kendi hatasını taşır; önceki denemenin sonucu sızmamalı.
        lastAttemptError = nil
        lastAttemptTimedOut = false
        // Önceki adresin ölçümü bu adres için geçerli değil.
        lastInspectedURL = nil
        lastInspection = nil

        // Sağlayıcıya özel başlık gereksinimleri için ortak bir UA gönderilir.
        //
        // `AVURLAssetHTTPHeaderFieldsKey` Swift'e köprülenmemiş bir
        // Objective-C sabitidir; anahtar bu yüzden dize olarak verilir.
        // Değer `PlaybackDiagnostics` ile **aynı** kaynaktan gelir: teşhis
        // ölçümü farklı bir UA gönderirse gerçek oynatma koşulunu yansıtmaz ve
        // "sunucu UA'yı engelliyor" teşhisi yanlış çıkardı.
        let asset = AVURLAsset(
            url: url,
            options: [
                PlaybackDiagnostics.headerFieldsKey: ["User-Agent": PlaybackDiagnostics.userAgent],
            ]
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
        // Gözlemci bu adres için zaten bir hata yazdıysa o korunur; motor
        // hatası süre aşımından daha açıklayıcıdır.
        if lastAttemptError == nil {
            lastAttemptTimedOut = true
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
        // VOD konumu **temizlemeden önce** yakalanır.
        //
        // Neden: `persistPosition()` çağrıldığında `currentItem` ve
        // `currentTime` henüz yerindeyse kayıt yapılabilir; ama `stop()`
        // bunları hemen aşağıda sıfırlar. Dışarıdan `Task { await
        // persistPosition() }` şeklinde çağrıldığında görev ana aktör
        // kuyruğunda beklerken `stop()` çoktan çalışmış olur ve kayıt
        // `guard let item = currentItem` satırında düşer. Sonuç: film
        // yarıda kapatıldığında konum hiç saklanmaz ve "kaldığı yerden
        // devam" çalışmaz. Bu yüzden değerler burada alınır ve yazma işi
        // arka planda yapılır.
        let pendingPosition: (any MediaItem, Double, Double?)?
        if !isLive, currentTime > 0, let item = currentItem {
            pendingPosition = (item, currentTime, duration)
        } else {
            pendingPosition = nil
        }

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
        lastAttemptError = nil
        lastAttemptTimedOut = false
        lastFailedURL = nil
        lastInspectedURL = nil
        lastInspection = nil
        currentItem = nil

        // Yakalanan konum, durum temizlendikten sonra yazılır.
        if let (savedItem, savedSeconds, savedDuration) = pendingPosition {
            Task { [recents] in
                await recents?.savePosition(
                    for: savedItem,
                    seconds: savedSeconds,
                    duration: savedDuration
                )
            }
        }
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
                    // Ham hata saklanır; kullanıcıya gösterilecek metin tüm
                    // adaylar tükendiğinde `PlaybackDiagnostics` ile üretilir.
                    // `localizedDescription` **kullanılmaz**: İngilizce gelir ve
                    // gerçek nedeni (kodek/konteyner) söylemez.
                    self.lastAttemptError = item.error
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
                // Yayın **başladıktan sonra** kesildi: aday denemesi değil,
                // oturumun düşmesidir. Yine de neden ölçülür — sunucu reddi,
                // zaman aşımı ve ağ kopması burada da ayırt edilebilir.
                let failure = PlaybackDiagnostics.classify(
                    error: error,
                    timedOut: false,
                    inspection: nil,
                    extensionHint: self.currentItem?.streamURL.pathExtension.lowercased() ?? ""
                )
                Log.player.error(
                    "Yayın kesildi: \(failure.technicalCode, privacy: .public)"
                )
                // Ayırt edilebilen bir neden varsa (sunucu reddi, ağ kopması)
                // o gösterilir. Neden bulunamazsa "yayın açılamadı" demek
                // yanlış olurdu: yayın açılmıştı, **kesildi**.
                let message = failure.kind == .unknown
                    ? L.f("player.error.technical", L.t("player.error.interrupted"), failure.technicalCode)
                    : failure.fullMessage
                self.state = .failed(message: message)
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
    /// VOD ve dizilerde de tek tahmine güvenilmez; olasılık sırasına göre
    /// birden çok adres denenir (ayrıntılı gerekçe aşağıda, VOD dalında).
    /// Sağlayıcının bildirdiği uzantı desteklenmiyorsa veya beyan gerçekle
    /// uyuşmuyorsa oynatma yine de başlayabilir; hiçbiri tutmazsa hata
    /// kullanıcıya açıkça bildirilir.
    ///
    /// Uzantı değiştirmek **kodeği değiştirmez**: sağlayıcı `.mp4` uzantılı bir
    /// adreste AC3 ses sunuyorsa hiçbir aday açılmaz. Bu durumda denemenin
    /// başarısızlığı bir adres sorunu değil, cihazın çözemediği bir biçimdir —
    /// ayrım `PlaybackDiagnostics` ile yapılır.
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

        // VOD/dizi: burada **tek aday** denemek yanlıştı.
        //
        // Daha önce yedek yalnızca sağlayıcının çözülemeyen bir konteyner
        // bildirdiği durumda üretiliyordu (`mkv`, `avi`, …). Sağlayıcı
        // oynatılabilir görünen bir uzantı bildirdiğinde liste tek elemana
        // düşüyor ve o adres tutmazsa kullanıcı doğrudan hata uyarısı
        // görüyordu. Canlı yayın bu tuzağa düşmez, çünkü orada uzantıdan
        // bağımsız olarak **her zaman** iki aday üretilir (`[m3u8, ts]`) —
        // "canlı çalışıyor, film çalışmıyor" farkının yapısal kaynağı buydu.
        //
        // Sağlayıcı beyanı ile gerçek dosya sık sık uyuşmaz: `container_extension`
        // "mkv" derken adres `.mp4` olarak çalışır, ya da uzantı doğru olmasına
        // karşın sunucu farklı bir biçim döndürür. Tek tahmine güvenmek yerine
        // olasılık sırasına göre birkaç adres denenir.
        //
        // Sıra: asıl adres → `mp4` → `m3u8`.
        //   * `mp4`: Xtream VOD'un standart biçimi.
        //   * `m3u8`: VOD için standart yol **değildir** (o yüzden en sonda),
        //     ama VOD'u HLS olarak da paketleyen paneller vardır. Bir deneme
        //     daha yapmak, kullanıcıya kesin bir hata göstermekten iyidir.
        let ext = primary.pathExtension.lowercased()
        var candidates: [URL] = [primary]

        if ext != "mp4", let mp4 = replacingExtension(of: primary, with: "mp4") {
            candidates.append(mp4)
        }
        if ext != "m3u8", let hls = replacingExtension(of: primary, with: "m3u8") {
            candidates.append(hls)
        }
        return candidates
    }

    /// Adresin yol uzantısını değiştirir. Uzantı yoksa `nil` döner; böylece
    /// anlamsız bir adres üretilmez.
    ///
    /// - Important: İşlem **kodlanmış** yol üzerinde yapılır, çözülmüş yol
    ///   üzerinde değil. Ölçülmüş kusur: eski kod `url.path` (çözülmüş) alıp
    ///   `components.path` ayarlayıcısına veriyordu; o ayarlayıcı `/`
    ///   karakterini **kodlamaz**. Şifresinde eğik çizgi olan bir kullanıcıda
    ///   asıl adreste `%2F` olarak kodlanmış karakter çözülüp ham `/` olarak
    ///   geri yazılıyor, yol bir fazla parçaya bölünüyor ve kimlik bilgisi
    ///   yanlış okunuyordu. Belirti sinsiydi: **yalnızca yedek adres** bozulur,
    ///   asıl adres doğru kalır — yani kimi film açılır, kimi açılmaz.
    ///
    ///   Not: ilk bakışta akla gelen "iki kez kodlama" (`%2540`) kusuru
    ///   burada **yoktu**; eski kod çözüp yeniden kodladığı için tur
    ///   gidiş-dönüşü kararlıydı. Bu, ölçülerek elenen bir varsayımdır.
    private static func replacingExtension(of url: URL, with newExtension: String) -> URL? {
        let encodedPath = url.percentEncodedPath
        guard let lastSlash = encodedPath.lastIndex(of: "/") else { return nil }

        let lastSegment = encodedPath[encodedPath.index(after: lastSlash)...]
        // Uzantı son parçanın içinde aranır: üst dizinlerdeki noktalar
        // (`/a.b/c/9`) uzantı sanılmamalıdır.
        guard let dot = lastSegment.lastIndex(of: "."),
              dot != lastSegment.startIndex else { return nil }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.percentEncodedPath = "\(encodedPath[..<dot]).\(newExtension)"
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
