import Combine
import Foundation
import UIKit
import VLCKit

/// libvlc (VLCKit) tabanlı oynatma motoru.
///
/// **Neden `AVPlayer` bırakıldı:** ölçüm kesin sonuç verdi — sağlayıcı filmleri
/// ve dizileri **yalnızca Matroska (`.mkv`)** olarak sunuyor ve `AVFoundation`
/// çerçevesinin Matroska demuxer'ı yoktur. Bu bir uygulama kusuru değil, çerçeve
/// sınırıdır; uzantıyı değiştirmek de kurtarmaz, çünkü sunucu diğer
/// uzantılarda gövdeyi **boş** döndürüyor (bkz. `scripts/xtream_teshis.py`).
/// Eksik olan şey yedek bir adres değil, bir **demuxer**'dı. libvlc Matroska,
/// AVI, WebM, ham MPEG-TS ve neredeyse tüm ses kodeklerini çözer.
///
/// **Teşhis artık okunuyor, tahmin edilmiyor.** `AVPlayer` döneminde hata nedeni
/// dolaylı kanıttan kestiriliyordu ve üç tur boyunca "Oynatma başlatılamadı."
/// cümlesinden öteye geçilemedi. libvlc başarısızlığın nedenini kendi
/// günlüğünde açıkça yazar; bu motor o günlüğü `VLCLogger` ile yakalar ve
/// `VLCDiagnostics` ile sınıflandırır.
///
/// **Delege köprüsü:** libvlc olayları kendi iş parçacıklarından bildirir.
/// `VLCMediaPlayerDelegate` yöntemlerini doğrudan bu `@MainActor` sınıfta
/// uygulamak, arka plan iş parçacığından çağrıldığında çalışma anında tuzağa
/// düşerdi. Bu yüzden araya izole olmayan bir köprü (`EngineBridge`) konur ve
/// geri çağrılar ana aktöre taşınır. Aynı desen `PictureInPictureController`
/// içinde de kullanılır.
@MainActor
final class VLCPlayerEngine: NSObject, ObservableObject, PlaybackProviding {

    // MARK: - PlaybackProviding

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentTitle: String?
    @Published private(set) var currentSubtitle: String?
    @Published private(set) var isLive: Bool = false
    @Published private(set) var duration: Double?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var didResumeFromSavedPosition: Bool = false
    @Published private(set) var isBuffering: Bool = false

    /// Oynatıcı. Görüntü yüzeyi (`VideoSurfaceView`) `drawable` üzerinden bağlanır.
    let player = VLCMediaPlayer()

    // MARK: - İç durum

    private var currentItem: (any MediaItem)?
    private var savedPosition: Double = 0

    /// libvlc olaylarını ana aktöre taşıyan köprü. `player.delegate` zayıf
    /// tutulduğu için burada kuvvetli referansla saklanır.
    private let bridge = EngineBridge()

    /// Başlatma sonucu. `AVPlayer` dönemindeki `StartupOutcome` ile aynı işi
    /// görür: yedek adrese geçmek ve hatayı kullanıcıya bildirmek için
    /// başlatmanın gerçekten sonuçlandığını bilmek zorundayız.
    private enum StartupOutcome { case ready, failed }
    private var startupOutcome: StartupOutcome?
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?

    /// Yayın hiç açılamadı mı, yoksa açılıp **kesildi** mi?
    ///
    /// Ayrım kullanıcının deneyimi için önemli: açılmamış bir yayında "tekrar
    /// dene" anlamlıdır, kesilmiş bir yayında "başlatılamadı" demek yanlış olur.
    private var hasStartedPlaying = false

    /// `stop()` sırasında gelen `.stopped` bildirimi kesilme sanılmasın.
    private var isStopping = false

    /// Başlatma için beklenecek azami süre (saniye).
    private var startupTimeout: Double { isLive ? 12 : 20 }

    /// Sırayla denenen adresler.
    private var candidateURLs: [URL] = []
    private var candidateIndex = 0

    /// Yükleme nesli: bekleyen eski bir döngünün yeni yayının durumunu ezmesini
    /// engeller (bkz. `attemptPlayback(generation:)`).
    private var attemptGeneration = 0

    /// Konumun diske yazılma sıklığı (saniye).
    private let positionSaveInterval: Double = 10
    private var lastSavedPosition: Double = 0

    private let recents: RecentsRepository?
    private let audioSession = AudioSessionManager.shared

    /// libvlc'nin ağ tamponu (ms). Canlıda küçük tutulur ki kanal geçişi
    /// hızlandırılsın; VOD'da daha büyük tampon takılmayı önler.
    private var networkCaching: Int { isLive ? 800 : 3000 }

    // MARK: - Kurulum

    init(recents: RecentsRepository? = nil) {
        self.recents = recents
        super.init()
        configureLibrary()
        configurePlayer()
        wireBridge()
        wireRemoteCommands()
    }

    /// libvlc'nin günlüğünü ve tanıtım bilgisini ayarlar.
    ///
    /// `loggers` **dizi olarak atanır**: `VLCLibrary` bu sürümde
    /// `addLogger:`/`removeLogger:` metodlarını sunmuyor, yalnızca
    /// `loggers` özelliğini taşıyor. Varsayılanı `nil` olduğu için tek bir
    /// logger atamak yeterlidir.
    private func configureLibrary() {
        let library = VLCLibrary.shared()
        library.loggers = [VLCLogger.shared]

        // Sağlayıcıya kendini tanıtan ad. Teşhis araçları
        // (`scripts/xtream_teshis.py`) **aynı** adı göndermek zorundadır; farklı
        // bir ad gönderilseydi ölçüm gerçek oynatma koşulunu yansıtmaz ve
        // "sunucu uygulamayı engelliyor" teşhisi yanlış çıkardı.
        library.setHumanReadableName("IPiOS", withHTTPUserAgent: PlaybackDiagnostics.userAgent)
    }

    private func configurePlayer() {
        player.delegate = bridge
        // Tek ölçekleme kipi: görüntü **her zaman** oranı korunarak sığdırılır.
        //
        // Canlı yayında daha önce ekranı dolduran kip kullanılıyordu; o kip
        // taşan kenarları kırpar ve yayının bir kısmı hiç görünmez (kanal
        // logoları, alt bantlar, skor tabelaları). Kullanıcı bunu "görüntü
        // sığmıyor" olarak bildirdi. Canlı ile VOD arasında davranış farkı
        // olması da beklenmedikti.
        player.videoFitMode = .smaller
        // Kanal değişiminde eski yayının görüntüsü bir an görünmesin.
        player.drawable = nil
        player.timeChangeUpdateInterval = 0.5
        player.minimalTimePeriod = 500_000
    }

    /// Köprü geri çağrılarını ana aktördeki işleyicilere bağlar.
    private func wireBridge() {
        bridge.onState = { [weak self] newState in
            self?.handle(state: newState)
        }
        bridge.onTime = { [weak self] seconds in
            self?.handle(time: seconds)
        }
        bridge.onLength = { [weak self] seconds in
            guard seconds.isFinite, seconds > 0 else { return }
            self?.duration = seconds
        }
        bridge.onBuffering = { [weak self] progress in
            guard let self else { return }
            // `progress` [0,1] aralığındadır. Yalnızca ilk kare gelmeden önce
            // gösterilir; oynatma başladıktan sonraki kısa tamponlamalar
            // kullanıcıya gösterge olarak yansıtılmaz (yayın zaten görünüyor).
            self.isBuffering = progress < 1.0 && (!self.hasStartedPlaying || !self.state.isPlaying)
        }
    }

    private func wireRemoteCommands() {
        audioSession.onPlay = { [weak self] in self?.play() }
        audioSession.onPause = { [weak self] in self?.pause() }
        audioSession.onToggle = { [weak self] in self?.togglePlayPause() }
        audioSession.onSkipForward = { [weak self] seconds in self?.seek(by: seconds) }
        audioSession.onSkipBackward = { [weak self] seconds in self?.seek(by: -seconds) }
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
        hasStartedPlaying = false
        state = .loading(item: item.title)

        audioSession.activate()

        if !isLive, let saved = startAt ?? resumePosition(for: item), saved > 15 {
            savedPosition = saved
            didResumeFromSavedPosition = true
        } else {
            savedPosition = 0
        }
        lastSavedPosition = savedPosition

        await recents?.record(item)

        candidateURLs = Self.playbackCandidates(for: item, isLive: isLive)
        candidateIndex = 0

        attemptGeneration += 1
        await attemptPlayback(generation: attemptGeneration)
    }

    // MARK: - Adres denemeleri

    /// Adayları sırayla dener; ilk açılan adres oynatılır.
    ///
    /// VLC ile aday listesi **kısaldı**: Matroska artık çözülebildiği için
    /// `AVPlayer` dönemindeki "uzantıyı değiştirip tekrar dene" hilesi
    /// gereksizdir ve zararlıydı — sunucu o uzantılarda gövdeyi boş döndürüyor,
    /// yani her yedek deneme kullanıcıya sadece gecikme olarak yansıyordu.
    /// Yine de liste boş bırakılmaz: sağlayıcı beyanı ile gerçek adres sık sık
    /// uyuşmaz ve tek bir tahmine güvenmek kırılgandır.
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

            guard generation == attemptGeneration else { return }

            guard startupOutcome == .ready else {
                candidateIndex += 1
                continue
            }

            state = .playing(item: currentItem?.title ?? "")
            updateNowPlaying()
            return
        }

        // `stop()` aday listesini boşaltmışsa buraya hatasız düşülür; aksi
        // hâlde kapatılmış bir oynatıcıda hata uyarısı açılırdı.
        guard generation == attemptGeneration, !candidateURLs.isEmpty else { return }

        // Teşhis libvlc'nin **kendi günlüğünden** okunur. Bu yüzden ölçüm için
        // ayrıca ağa çıkılmaz: `AVPlayer` döneminde akışı yeniden indirip kodek
        // okumak gerekiyordu, libvlc ise ne yaptığını zaten yazıyor.
        let profile = VLCDiagnostics.profile(of: player)
        let failure = VLCDiagnostics.classify(
            profile: profile,
            logLines: VLCLogger.shared.problemLines(),
            extensionHint: currentItem?.streamURL.pathExtension.lowercased() ?? "",
            timedOut: lastAttemptTimedOut
        )

        Log.player.error(
            "Oynatma başarısız: \(failure.technicalCode, privacy: .public) — denenen adres sayısı: \(self.candidateURLs.count)"
        )

        // **Kaldırılan özel durum:** `AVPlayer` döneminde kaynağın adresi ham
        // MPEG-TS ise kullanıcıya "bu biçim oynatılamıyor" denirdi, çünkü
        // `AVPlayer` ham TS konteynerini çözemezdi. libvlc çözer. Bu dal
        // bırakılsaydı, **çalışan** bir yayın için bile yanlış bir uyarı
        // gösterilirdi; kaldırılması bir sadeleştirme değil, düzeltmedir.
        state = .failed(message: failure.fullMessage)
    }

    /// Tek bir adres için `VLCMedia` kurar ve oynatmayı başlatır.
    private func startItem(with url: URL) {
        startupOutcome = nil
        lastAttemptTimedOut = false
        isBuffering = true

        // Önceki oturumun günlüğü temizlenir: çoktan çözülmüş bir sorunun
        // satırları yeni teşhise karışırsa kullanıcı yanlış yöne gönderilir.
        VLCLogger.shared.reset()

        guard let media = VLCMedia(url: url) else {
            // Adres kurulamadı: ağa hiç çıkılmaz, doğrudan başarısız sayılır.
            startupOutcome = .failed
            return
        }

        // Ağ tamponu: sağlayıcının yavaş panellerinde takılmayı önler.
        media.addOption(":network-caching=\(networkCaching)")
        // User-Agent: bazı paneller tanımadıkları istemcileri reddediyor.
        // Demuxer seçimiyle **ilgisi yoktur** — hangi demuxer'ın kullanılacağına
        // libvlc içeriğe bakarak karar verir; bu seçenek yalnızca HTTP
        // başlığını belirler.
        media.addOption("\(PlaybackDiagnostics.userAgentOptionKey)=\(PlaybackDiagnostics.userAgent)")

        player.media = media
        player.play()
    }

    /// Başlatma sonuçlanana kadar bekler; süre aşılırsa denemeyi başarısız sayar.
    private func waitForReadyOrFailure() async {
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
        lastAttemptTimedOut = true
        signalReady(.failed)
    }

    /// Bekleyeni (varsa) tek kez serbest bırakır ve sonucu kaydeder.
    private func signalReady(_ outcome: StartupOutcome) {
        guard startupOutcome == nil else { return }
        startupOutcome = outcome

        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil

        guard let continuation = readyContinuation else { return }
        readyContinuation = nil
        continuation.resume()
    }

    /// Deneme süre aşımına mı uğradı? Süre aşımı hatasız gelir, bu yüzden
    /// ayrı bir bayrakta tutulur.
    private var lastAttemptTimedOut = false

    // MARK: - libvlc olayları

    private func handle(state newState: VLCMediaPlayerState) {
        switch newState {
        case .opening:
            if !hasStartedPlaying { isBuffering = true }

        case .playing:
            hasStartedPlaying = true
            isBuffering = false
            // Kaydedilmiş konum, oynatma gerçekten başladıktan sonra uygulanır:
            // libvlc arama isteğini ancak akış çözüldükten sonra işleyebilir.
            if savedPosition > 0 {
                seek(to: savedPosition)
                savedPosition = 0
            }
            if let item = currentItem {
                state = .playing(item: item.title)
            }
            updateNowPlaying()
            signalReady(.ready)

        case .paused:
            if let item = currentItem {
                state = .paused(item: item.title)
            }
            updateNowPlaying()

        case .stopping:
            isBuffering = true

        case .stopped:
            handleStopped()

        case .error:
            Log.player.error("libvlc oynatıcı hata durumuna geçti")
            signalReady(.failed)
            // Yayın hiç açılmadıysa deneme döngüsü yedek adrese geçer; açılmışsa
            // bu bir kesilmedir ve doğrudan bildirilir.
            if hasStartedPlaying {
                reportInterruption()
            }

        case .nothingSpecial:
            break

        @unknown default:
            break
        }
    }

    /// `.stopped` durumu iki farklı olayı temsil eder: içerik sonuna kadar
    /// oynadı ya da yayın düştü. Ayrım konumdan yapılır.
    private func handleStopped() {
        guard !isStopping else { return }

        if !hasStartedPlaying {
            // Hiç başlamadıysa bu bir deneme hatasıdır; döngü yedek adrese geçer.
            signalReady(.failed)
            return
        }

        isBuffering = false
        if player.position >= 0.95 {
            state = .finished
            if let item = currentItem {
                Task { [recents] in
                    await recents?.clearPosition(for: item)
                }
            }
        } else {
            reportInterruption()
        }
    }

    /// Yayın **başladıktan sonra** kesildi.
    private func reportInterruption() {
        let failure = VLCDiagnostics.classifyInterruption(
            logLines: VLCLogger.shared.problemLines()
        )
        Log.player.error("Yayın kesildi: \(failure.technicalCode, privacy: .public)")
        isBuffering = false
        state = .failed(message: failure.fullMessage)
    }

    private func handle(time seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        currentTime = seconds

        // VOD'da konum periyodik olarak diske yazılır.
        if !isLive, abs(seconds - lastSavedPosition) >= positionSaveInterval {
            Task { await persistPosition() }
        }
    }

    // MARK: - Kontroller

    func play() {
        guard let item = currentItem else { return }
        guard !state.isFailed else { return }

        if case .finished = state {
            seek(to: 0)
        }
        if case .idle = state { return }

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
        // VOD konumu temizlemeden **önce** yakalanır (ayrıntılı gerekçe:
        // `PlayerViewModel.stop()` konumu yazmayı ayrı bir göreve bırakır ve o
        // görev ana aktör kuyruğunda beklerken bu metot çoktan çalışmış olur;
        // değerler burada alınmazsa film yarıda kapatıldığında konum hiç
        // saklanmaz).
        let pendingPosition: (any MediaItem, Double, Double?)?
        if !isLive, currentTime > 0, let item = currentItem {
            pendingPosition = (item, currentTime, duration)
        } else {
            pendingPosition = nil
        }

        // libvlc'nin `.stopped` bildirimi kesilme sanılmasın.
        isStopping = true
        player.stop()
        player.media = nil
        isStopping = false

        signalReady(.failed)
        startupOutcome = nil
        candidateURLs = []
        candidateIndex = 0
        attemptGeneration += 1

        state = .idle
        currentTitle = nil
        currentSubtitle = nil
        currentTime = 0
        duration = nil
        isLive = false
        isBuffering = false
        hasStartedPlaying = false
        didResumeFromSavedPosition = false
        lastAttemptTimedOut = false
        savedPosition = 0
        currentItem = nil

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
        guard currentItem != nil, !isLive else { return }
        // Canlı yayında libvlc aramayı desteklemez (`isSeekable` yanlış döner);
        // istek sessizce yok sayılırdı ama kullanıcıya "atladı" izlenimi
        // vermemek için konum da güncellenmez.
        let upperBound = duration.map { max($0 - 1, 0) } ?? seconds
        let target = min(max(seconds, 0), upperBound)

        player.time = VLCTime(int: Int32(target * 1000))
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

    /// Ses seviyesi 0...1.
    ///
    /// İki dönüşüm gerekir ve ikisi de derleyici tarafından doğrulandı:
    ///
    /// 1. `player.audio` **opsiyoneldir** (`readonly, weak`); oynatıcı henüz
    ///    ses çıkışı kurmadıysa `nil` olur. Bu yüzden `?` ile yazılır —
    ///    kuvvetli çözme, ses ayarı ekran açılışında uygulandığında çökerdi.
    /// 2. `volume` bir **tamsayı** ölçektir (0–100 ve üzeri) ve Swift'te
    ///    `Int32` olarak köprülenir. `Int` yazmak derleme hatası verir; ham
    ///    0...1 değerini vermek ise sesi ya tamamen kapatır ya sonuna kadar
    ///    açar (eski kusur: "ses çıkmuyor" sanılıp boşuna kodek aranırdı).
    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        player.audio?.volume = Int32(clamped * 100)
    }

    // MARK: - Adres seçimi

    /// Denerken kullanılacak adres listesini üretir.
    ///
    /// **VLC ile liste belirgin biçimde kısaldı.** `AVPlayer` döneminde amaç,
    /// çözülemeyen konteyneri atlatmak için uzantıyı değiştirmekti. Ölçüm bu
    /// yaklaşımın işe yaramadığını gösterdi: sağlayıcı `.mkv` dışındaki
    /// uzantılarda **boş gövde** döndürüyor, yani her yedek deneme kullanıcıya
    /// yalnızca gecikme olarak yansıyordu. libvlc Matroska'yı doğrudan çözer.
    ///
    /// Yine de tek aday bırakılmaz: sağlayıcı beyanı (`container_extension`) ile
    /// gerçek adres sık sık uyuşur ama her zaman değil, ve canlı yayında aynı
    /// kanal `.m3u8` ya da ham `.ts` olarak sunulabilir. Sıra korunur, çünkü
    /// asıl adres her zaman en olası olandır.
    static func playbackCandidates(for item: any MediaItem, isLive: Bool) -> [URL] {
        let primary = item.streamURL

        if isLive {
            // Canlıda her iki taşıyıcı da libvlc tarafından çözülebilir; birini
            // seçmek yerine ikisi de denenir.
            let m3u8 = replacingExtension(of: primary, with: "m3u8")
            let ts = replacingExtension(of: primary, with: "ts")

            var candidates: [URL] = [primary]
            for url in [m3u8, ts] where url != nil {
                if !candidates.contains(url!) { candidates.append(url!) }
            }
            return candidates
        }

        // VOD/dizi: asıl adres, sağlayıcının beyan ettiği uzantıyı taşır ve
        // libvlc onu çözer. `mp4` yedeği korunur çünkü azınlıkta da olsa
        // VOD'u H.264/MP4 olarak sunan paneller vardır; `.m3u8` yedeği
        // kaldırıldı, çünkü VOD'un HLS olarak paketlendiği bir panel bu
        // sağlayıcıda gözlenmedi ve her yedek deneme zaman aşımına kadar
        // bekleyip kullanıcıya gecikme olarak yansıyor.
        let ext = primary.pathExtension.lowercased()
        var candidates: [URL] = [primary]

        if ext != "mp4", let mp4 = replacingExtension(of: primary, with: "mp4") {
            candidates.append(mp4)
        }
        return candidates
    }

    /// Adresin yol uzantısını değiştirir. Uzantı yoksa `nil` döner.
    ///
    /// - Important: İşlem **kodlanmış** yol üzerinde yapılır, çözülmüş yol
    ///   üzerinde değil. Ölçülmüş kusur: eski kod `url.path` (çözülmüş) alıp
    ///   `components.path` ayarlayıcısına veriyordu; o ayarlayıcı `/`
    ///   karakterini **kodlamaz**. Şifresinde eğik çizgi olan bir kullanıcıda
    ///   asıl adreste `%2F` olarak kodlanmış karakter çözülüp ham `/` olarak
    ///   geri yazılıyor, yol bir fazla parçaya bölünüyor ve kimlik bilgisi
    ///   yanlış okunuyordu. Belirti sinsiydi: **yalnızca yedek adres** bozulur,
    ///   asıl adres doğru kalır — yani kimi film açılır, kimi açılmaz.
    private static func replacingExtension(of url: URL, with newExtension: String) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let encodedPath = components.percentEncodedPath
        guard let lastSlash = encodedPath.lastIndex(of: "/") else { return nil }

        let lastSegment = encodedPath[encodedPath.index(after: lastSlash)...]
        // Uzantı son parçanın içinde aranır: üst dizinlerdeki noktalar
        // (`/a.b/c/9`) uzantı sanılmamalıdır.
        guard let dot = lastSegment.lastIndex(of: "."),
              dot != lastSegment.startIndex else { return nil }

        var updated = components
        updated.percentEncodedPath = "\(encodedPath[..<dot]).\(newExtension)"
        return updated.url
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

// MARK: - Köprü

/// libvlc olaylarını ana aktöre taşıyan izole olmayan köprü.
///
/// `VLCMediaPlayerDelegate` yöntemleri libvlc'nin kendi iş parçacıklarından
/// çağrılır. Bunları doğrudan `@MainActor` bir sınıfta uygulamak çalışma
/// anında tuzağa düşerdi; köprü geri çağrıları taşır ve döngüsel referansı
/// önlemek için motoru kuvvetli tutmaz (yalnızca kapanışlar saklanır).
///
/// Yalnızca değer tipleri (enum, `Double`, `Float`) taşınır; bunlar `Sendable`
/// olduğu için aktörler arası geçiş güvenlidir.
private final class EngineBridge: NSObject, VLCMediaPlayerDelegate {

    var onState: (@MainActor (VLCMediaPlayerState) -> Void)?
    var onTime: (@MainActor (Double) -> Void)?
    var onLength: (@MainActor (Double) -> Void)?
    var onBuffering: (@MainActor (Float) -> Void)?

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        let handler = onState
        Task { @MainActor in handler?(newState) }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        // `VLCTime.intValue` **milisaniye** döner; arayüz saniye ile çalışır.
        let milliseconds = Double(player.time.intValue)
        guard milliseconds.isFinite else { return }
        let handler = onTime
        Task { @MainActor in handler?(milliseconds / 1000) }
    }

    func mediaPlayerLengthChanged(_ length: Int64) {
        guard length > 0 else { return }
        let handler = onLength
        Task { @MainActor in handler?(Double(length) / 1000) }
    }

    func mediaPlayerBufferingChanged(_ progress: Float) {
        let handler = onBuffering
        Task { @MainActor in handler?(progress) }
    }
}
