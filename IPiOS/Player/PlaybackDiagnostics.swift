import AVFoundation
import CoreMedia
import Foundation

/// Oynatma başarısızlığının **ölçülebilir** nedeni.
///
/// Neden gerekli: kullanıcı "film açılmıyor" dediğinde uygulamanın verdiği
/// yanıt `AVPlayerItem.error.localizedDescription` idi. Bu metin çoğu zaman
/// "işlem tamamlanamadı" gibi hiçbir şey anlatmayan bir cümledir; asıl neden
/// hatanın `NSUnderlyingErrorKey` zincirinde ya da **dosyanın kendisinde**
/// (çözülemeyen ses/görüntü kodeği) durur. Sonuç: kullanıcı her seferinde
/// aynı belirsiz uyarıyı görüyor ve sorun teşhis edilemiyordu.
///
/// Bu tip, nedeni tahmin etmek yerine **ölçer**: akışın taşıdığı kodekler
/// AVFoundation'ın kendi API'siyle okunur, hata zinciri koddan koda yürünür.
enum PlaybackFailureKind: Equatable {
    /// Ses kodeği cihazda çözülemiyor. Görüntü kodeği destekli olsa bile
    /// öğenin tamamı düşer; kullanıcı hiç görüntü görmez.
    case unsupportedAudioCodec(name: String)
    /// Görüntü kodeği cihazda çözülemiyor.
    case unsupportedVideoCodec(name: String)
    /// Taşıyıcı biçim tanınamadı (MKV, AVI, WebM, ham MPEG-TS…).
    case unrecognizedContainer(extensionHint: String)
    /// Sunucu yayını vermeyi reddetti (ör. 403, 404, 5xx).
    case rejected(status: Int)
    /// Sunucu kimliği kabul etmedi.
    case unauthorized
    /// Sunucuya ulaşılamadı.
    case offline
    /// Sunucu zamanında yanıt vermedi.
    case timedOut
    /// Hiçbiri ayırt edilemedi.
    case unknown
}

/// Sınıflandırılmış başarısızlık: kullanıcıya gösterilecek **açıklama** ve
/// teşhis için **kod**.
struct PlaybackFailure: Equatable {

    let kind: PlaybackFailureKind

    /// Yalnızca kodlardan oluşan, dile bağlı olmayan teşhis satırı.
    ///
    /// Neden kod: `AVFoundation` hata metinleri İngilizce gelir ve Türkçe
    /// arayüzde anlamsız bir gürültüdür. Alan adı + sayısal kod ise dilden
    /// bağımsızdır ve doğrudan aranabilir (`-11800`, `-12865`, `ac-3`).
    let technicalCode: String

    /// Kullanıcıya gösterilecek tam metin.
    var message: String {
        switch kind {
        case .unsupportedAudioCodec(let name):
            return L.f("player.error.codec.audio", name)
        case .unsupportedVideoCodec(let name):
            return L.f("player.error.codec.video", name)
        case .unrecognizedContainer(let hint):
            return L.f("player.error.container", hint.isEmpty ? "—" : hint)
        case .rejected(let status):
            // Durum kodu okunamadıysa (0) "%d" yerine kodsuz metin gösterilir;
            // "kod: 0" demek kullanıcıyı yanıltırdı.
            return status > 0
                ? L.f("player.error.rejected", status)
                : L.t("player.error.rejectedNoCode")
        case .unauthorized:
            return L.t("error.unauthorized")
        case .offline:
            return L.t("error.sourceUnreachable")
        case .timedOut:
            return L.t("player.error.timeout")
        case .unknown:
            return L.t("player.error.startFailed")
        }
    }

    /// Açıklama + teşhis satırı. Teşhis yoksa yalnızca açıklama döner; boş
    /// satır ya da "Teknik: " artığı bırakılmaz.
    var fullMessage: String {
        guard !technicalCode.isEmpty else { return message }
        return L.f("player.error.technical", message, technicalCode)
    }
}

/// Akışın gerçekten ne taşıdığına dair **ölçüm**.
struct StreamInspection: Equatable {

    /// Dört harfli kodek kimlikleri (ör. `mp4a`, `ac-3`, `avc1`).
    var audioCodecs: [String] = []
    var videoCodecs: [String] = []

    /// Taşıyıcı çözülebildi mi? `false` ise konteyner ya tanınmadı ya da
    /// sunucu okunabilir bir yanıt vermedi.
    var isReadable: Bool = false

    /// Taşıyıcı hiç okunamadı.
    static let unreadable = StreamInspection()

    /// Teşhis satırı için ölçülen kodekler (dile bağlı olmayan).
    var codecSummary: String {
        var parts: [String] = []
        if !videoCodecs.isEmpty { parts.append(videoCodecs.joined(separator: "+")) }
        if !audioCodecs.isEmpty { parts.append(audioCodecs.joined(separator: "+")) }
        return parts.joined(separator: " · ")
    }
}

/// Oynatma hatalarını sınıflandıran ve akışı denetleyen yardımcılar.
///
/// Neden `nonisolated`: yalnızca saf girdi/çıktı ile çalışır; ana aktörde
/// yapılacak iş yoktur. Ağ beklemesi oynatıcıyı kilitlememelidir.
enum PlaybackDiagnostics {

    /// `AVURLAsset` seçenekleri anahtarı.
    ///
    /// `AVURLAssetHTTPHeaderFieldsKey` Objective-C sabiti Swift'e
    /// köprülenmediği için değeri burada tutulur; sihirli dize tek yerde kalır.
    static let headerFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"

    /// Oynatıcının sağlayıcıya gönderdiği uygulama adı.
    ///
    /// Teşhis denetimi de **aynı** adı göndermek zorundadır; farklı bir ad
    /// gönderilseydi ölçüm gerçek oynatma koşulunu yansıtmazdı.
    static let userAgent = "IPiOS/1.0 (iOS)"

    /// AVPlayer'ın **çözemediği** ses kodekleri.
    ///
    /// IPTV filmlerinde çok yaygındır. Kritik nokta: desteklenmeyen bir ses
    /// kodeği, görüntü kodeği destekli olsa bile `AVPlayerItem`'ın tamamını
    /// düşürür. Kullanıcı bu yüzden "sadece isimler ve posterler geliyor,
    /// video oynamıyor" der.
    static let unsupportedAudio: [String: String] = [
        "ac-3": "AC3",
        "ec-3": "E-AC3",
        "dtsc": "DTS",
        "dtsh": "DTS-HD",
        "dtsl": "DTS",
        "dtse": "DTS Express",
        "mlpa": "TrueHD",
        "opus": "Opus",
    ]

    /// AVPlayer'ın **çözemediği** görüntü kodekleri.
    static let unsupportedVideo: [String: String] = [
        "av01": "AV1",
        "vp09": "VP9",
        "vp08": "VP8",
    ]

    // MARK: - AVFoundation hata kodları

    /// Sayısal `AVFoundationErrorDomain` kodları.
    ///
    /// Neden adlar değil de sayılar: `AVError.Code` sabitlerinin Swift adları
    /// sürümler arasında değişir ve burada bir kez **var olmayan** bir ad
    /// kullanıldı (`noSourceMedia`), dosya CI'da derlenmedi. Sayısal değerler
    /// Objective-C sabitleriyle aynıdır ve değişmez. Eşlenen kodlar yalnızca
    /// anlamı **kesin bilinen** olanlardır: yanlış bir açıklama üretmek, hiç
    /// açıklama üretmemekten kötüdür (ham kod `technicalCode` ile kullanıcıya
    /// yine taşınır).
    /// `AVErrorContentIsNotAuthorized`.
    private static let contentIsNotAuthorizedCode = -11856
    /// `AVErrorContentIsUnavailable`.
    private static let contentIsUnavailableCode = -11857
    /// `AVErrorFileFormatNotRecognized`.
    private static let fileFormatNotRecognizedCode = -11828
    /// `AVErrorFileFailedToParse`.
    private static let fileFailedToParseCode = -11829
    /// `AVErrorInvalidSourceMedia`.
    private static let invalidSourceMediaCode = -11833

    // MARK: - Sınıflandırma

    /// Hatayı ve ölçümü tek bir nedene indirger.
    ///
    /// Sıra önemlidir: en **kesin** kanıttan en zayıf tahmine inilir.
    ///
    /// 1. Ağ/kimlik hataları — sunucu hiç konuşmadıysa kodek aranmaz.
    /// 2. Ölçülen kodekler — kanıt doğrudan dosyadan gelir, en güvenilir.
    /// 3. Zaman aşımı — "konteyner tanınmadı" demek yanıltıcı olurdu.
    /// 4. Konteyner — taşıyıcı hiç okunamadıysa.
    /// 5. Bilinmeyen.
    ///
    /// - Parameters:
    ///   - error: Son denemenin hatası (olmayabilir; zaman aşımı hatasız gelir).
    ///   - timedOut: Başlatma süresi aşıldı mı?
    ///   - inspection: Akış ölçümü. `nil` ise ölçüm yapılmadı (ör. canlı yayın).
    ///   - extensionHint: Teşhis metninde gösterilecek adres uzantısı.
    static func classify(
        error: Error?,
        timedOut: Bool,
        inspection: StreamInspection?,
        extensionHint: String
    ) -> PlaybackFailure {
        let chain = errorChain(error)

        // 1. Sunucu/ağ katmanı.
        if let kind = networkKind(error) {
            // `networkKind` konteyner nedenini uzantıyı bilmeden üretir
            // (`AVError` uzantıyı taşımaz); asıl uzantı burada tamamlanır ki
            // kullanıcıya "(—)" gibi boş bir parantez gösterilmesin.
            let resolved: PlaybackFailureKind
            if case .unrecognizedContainer(let hint) = kind, hint.isEmpty {
                resolved = .unrecognizedContainer(extensionHint: extensionHint)
            } else {
                resolved = kind
            }
            return PlaybackFailure(kind: resolved, technicalCode: chain.joined(separator: " ← "))
        }

        // 2. Ölçülen kodekler.
        if let inspection {
            if let code = inspection.audioCodecs.first(where: { unsupportedAudio[$0] != nil }) {
                return PlaybackFailure(
                    kind: .unsupportedAudioCodec(name: unsupportedAudio[code] ?? code),
                    technicalCode: joined(chain, inspection.codecSummary)
                )
            }
            if let code = inspection.videoCodecs.first(where: { unsupportedVideo[$0] != nil }) {
                return PlaybackFailure(
                    kind: .unsupportedVideoCodec(name: unsupportedVideo[code] ?? code),
                    technicalCode: joined(chain, inspection.codecSummary)
                )
            }
        }

        // 3. Zaman aşımı.
        if timedOut {
            return PlaybackFailure(
                kind: .timedOut,
                technicalCode: joined(chain, inspection?.codecSummary ?? "")
            )
        }

        // 4. Taşıyıcı hiç okunamadı.
        //    `inspection == nil` (ölçüm yapılmadı) buraya **girmez**: ölçüm
        //    yapılmadıysa "konteyner tanınmadı" demek kanıtsız bir iddia olur.
        if let inspection, !inspection.isReadable {
            return PlaybackFailure(
                kind: .unrecognizedContainer(extensionHint: extensionHint),
                technicalCode: chain.joined(separator: " ← ")
            )
        }

        // 5. Ayırt edilemedi. Teşhis satırı yine de **boş bırakılmaz**: kanıt
        //    yokluğunun kendisi bilgidir ve "hiçbir şey yok" demek, kullanıcının
        //    tekrar bildirmesi gereken bir belirsizlik yaratırdı.
        let code = joined(chain, inspection?.codecSummary ?? "")
        return PlaybackFailure(kind: .unknown, technicalCode: code.isEmpty ? "unknown" : code)
    }

    /// Ağ ve sunucu hatalarını ayırır.
    ///
    /// Yalnızca **kesin bilinen** kodlar eşlenir. Sayısal kodu tahmin edip
    /// yanlış bir açıklama üretmek, hiç açıklama üretmemekten kötüdür; bu
    /// yüzden her hata için ölçülen zincir `technicalCode` alanında ham
    /// olarak kullanıcıya taşınır.
    private static func networkKind(_ error: Error?) -> PlaybackFailureKind? {
        guard let nsError = error as NSError? else { return nil }

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return .timedOut
            case NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorDataNotAllowed:
                return .offline
            case NSURLErrorUserAuthenticationRequired,
                 NSURLErrorUserCancelledAuthentication:
                return .unauthorized
            case NSURLErrorBadServerResponse,
                 NSURLErrorResourceUnavailable:
                return .rejected(status: statusCode(from: nsError))
            default:
                break
            }
        }

        // Dikkat: `AVError.Code`'un Swift adları **kullanılmaz**. Bu adlar
        // sürümden sürüme değişebiliyor ve bir tanesi (`noSourceMedia`) hiç
        // yoktu — kod CI'da derlenmedi. Sayısal değerler ise köprüleme
        // davranışından bağımsız olarak sabittir.
        if nsError.domain == AVFoundationErrorDomain {
            switch nsError.code {
            case contentIsNotAuthorizedCode:
                return .unauthorized
            case contentIsUnavailableCode,
                 fileFormatNotRecognizedCode,
                 fileFailedToParseCode,
                 invalidSourceMediaCode:
                return .unrecognizedContainer(extensionHint: "")
            default:
                break
            }
        }

        // Sunucu reddi çoğu zaman yalnızca alt hata zincirinde görünür:
        // `AVFoundation` üst hatayı "-11800 bilinmeyen" olarak sarmalar,
        // gerçek HTTP kodu altta durur.
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSURLErrorDomain,
           underlying.code == NSURLErrorBadServerResponse || underlying.code == NSURLErrorResourceUnavailable {
            return .rejected(status: statusCode(from: underlying))
        }

        return nil
    }

    /// Hata zincirinden HTTP durum kodunu çıkarır; yoksa 0.
    ///
    /// `AVFoundation` durum kodunu `NSUnderlyingErrorKey` zincirinde ya da
    /// `NSError` nesnesinin kendi zincirinde taşıyabilir; ikisi de denenir.
    private static func statusCode(from error: NSError) -> Int {
        var current: NSError? = error
        var depth = 0
        while let nsError = current, depth < 4 {
            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorBadServerResponse || nsError.code == NSURLErrorResourceUnavailable,
               let status = nsError.userInfo["HTTPStatusCode"] as? Int,
               status > 0 {
                return status
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        // Durum kodu okunamadıysa 0 gösterilir; mesaj yine de anlamlıdır
        // ("sunucu reddetti") ve yanlış bir kod uydurulmaz.
        return 0
    }

    /// Hatayı alan adı + kod ikililerine indirger.
    ///
    /// Yalnızca kod gösterilir; `localizedDescription` **bilinçli olarak**
    /// gösterilmez (dile bağlıdır ve Türkçe arayüzde gürültüdür).
    private static func errorChain(_ error: Error?) -> [String] {
        var parts: [String] = []
        var current: NSError? = error.map { $0 as NSError }
        var depth = 0
        // Döngüye karşı derinlik sınırı: bozuk bir zincir sonsuz olabilir.
        while let nsError = current, depth < 4 {
            parts.append(nsError.code == 0 ? nsError.domain : "\(nsError.domain) \(nsError.code)")
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return parts
    }

    private static func joined(_ chain: [String], _ codecs: String) -> String {
        var parts = chain
        if !codecs.isEmpty { parts.append(codecs) }
        return parts.joined(separator: " ← ")
    }

    // MARK: - Ölçüm

    /// Akışın taşıdığı kodekleri **gerçekten** okur.
    ///
    /// Neden tahmin değil ölçüm: "AVPlayer bu kodeği çözemez" iddiasını
    /// sağlayıcının beyanına (`container_extension`) dayandırmak güvenilmez —
    /// beyan ile gerçek dosya sık sık uyuşmaz. Burada AVFoundation'ın kendi
    /// API'siyle format tanımları okunur.
    ///
    /// Önemli ayrım: konteyner **çözülebildiği** hâlde oynatma başarısız
    /// olabilir (MP4 + AC3). Bu durumda `isReadable` doğrudur ve kodek listesi
    /// gerçek suçluyu verir. Konteyner hiç çözülemiyorsa (MKV) `load` hata
    /// verir ve `isReadable` yanlış kalır.
    ///
    /// - Parameter timeout: Ölçüm için azami bekleme. Ağ yanıt vermezse
    ///   kullanıcıyı bekletmemek için ölçümden vazgeçilir.
    static func inspect(_ url: URL, timeout: Double = 8) async -> StreamInspection {
        let work = Task { await readTracks(url) }
        let limit = Task {
            try? await Task.sleep(for: .seconds(timeout))
            work.cancel()
        }
        defer { limit.cancel() }
        return await work.value
    }

    private static func readTracks(_ url: URL) async -> StreamInspection {
        let asset = AVURLAsset(
            url: url,
            options: [headerFieldsKey: ["User-Agent": userAgent]]
        )

        do {
            let tracks = try await asset.load(.tracks)
            var inspection = StreamInspection()
            inspection.isReadable = true

            for track in tracks {
                let descriptions = try await track.load(.formatDescriptions)
                for description in descriptions {
                    let code = fourCC(CMFormatDescriptionGetMediaSubType(description))
                    let mediaType = CMFormatDescriptionGetMediaType(description)
                    if mediaType == kCMMediaType_Audio {
                        inspection.audioCodecs.append(code)
                    } else if mediaType == kCMMediaType_Video {
                        inspection.videoCodecs.append(code)
                    }
                }
            }

            inspection.audioCodecs = dedupe(inspection.audioCodecs)
            inspection.videoCodecs = dedupe(inspection.videoCodecs)
            return inspection
        } catch {
            // Taşıyıcı okunamadı. Bu **bir sonuçtur**, hata değil: çağıran
            // taraf bunu "konteyner tanınmadı" olarak yorumlar.
            return .unreadable
        }
    }

    /// Dört harfli kodek kimliğini okunabilir metne çevirir.
    ///
    /// Yazdırılamayan baytlar `?` olur; böylece bozuk bir kimlik metni
    /// parantez içinde çöp karakterlerle doldurmaz.
    static func fourCC(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        let characters: [Character] = bytes.map { byte in
            (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "?"
        }
        return String(characters).trimmingCharacters(in: .whitespaces)
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
