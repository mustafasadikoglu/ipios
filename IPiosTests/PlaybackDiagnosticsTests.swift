import AVFoundation
import XCTest
@testable import IPiOS

/// Oynatma hatası sınıflandırmasının kurallarını doğrular.
///
/// Neden gerekli: üç tur boyunca kullanıcı yalnızca "Oynatma başlatılamadı."
/// cümlesini gördü ve sorun teşhis edilemedi. Bu cümle birbirinden tamamen
/// farklı üç kusuru aynı metne indiriyordu: cihazın çözemediği bir kodek,
/// tanınmayan bir konteyner ve sunucunun yayını reddetmesi. Sınıflandırma
/// yanlış sırayla yapılırsa kullanıcıya **yanlış** neden gösterilir — örneğin
/// sunucu 404 dönerken "kodek desteklenmiyor" denir ve kullanıcı boşuna
/// sağlayıcıdan başka bir sürüm ister. Bu yüzden sıra teste bağlanmıştır.
final class PlaybackDiagnosticsTests: XCTestCase {

    // MARK: - Yardımcılar

    private func inspection(
        audio: [String] = [],
        video: [String] = [],
        readable: Bool = true
    ) -> StreamInspection {
        StreamInspection(audioCodecs: audio, videoCodecs: video, isReadable: readable)
    }

    /// Ölçüm hiç yapılmadı (`nil`) ile "ölçüm yapıldı, taşıyıcı okunamadı"
    /// (`readable: false`) farklı sonuçlar üretmelidir.
    private func unreadable() -> StreamInspection {
        StreamInspection.unreadable
    }

    private func avError(_ code: Int) -> NSError {
        NSError(domain: AVFoundationErrorDomain, code: code)
    }

    private let unsupportedFormatCode = -11800

    /// `AVError` sabitlerinin **sayısal** değerleri. Swift adları yerine
    /// sayılar kullanılır çünkü adlar sürümden sürüme değişir ve bir kez
    /// var olmayan bir ad (`noSourceMedia`) yazıldığı için dosya derlenmedi.
    private let containerCode = -11828
    private let unauthorizedCode = -11856

    /// Aynı sayıya iki farklı anlam yüklenmemeli. Önceki kusur tam buydu:
    /// iki ayrı sabit aynı değeri taşıyordu ve sonuç sessizce yanlıştı.
    func testMappedAVErrorCodesAreDistinct() {
        XCTAssertNotEqual(containerCode, unauthorizedCode)
        XCTAssertNotEqual(containerCode, unsupportedFormatCode)
    }

    /// Eşlenen konteyner kodu gerçekten konteyner nedenini üretmeli.
    func testContainerCodeMapsToUnrecognizedContainer() {
        let failure = PlaybackDiagnostics.classify(
            error: avError(containerCode), timedOut: false, inspection: nil, extensionHint: "mkv"
        )
        guard case .unrecognizedContainer(let hint) = failure.kind else {
            return XCTFail("konteyner bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(hint, "mkv")
    }

    // MARK: - Gerçek senaryo

    /// Kullanıcının bildirdiği tablo: liste ve posterler geliyor, video
    /// oynamıyor. En yaygın nedeni H.264 görüntü + AC3 sestir; görüntü kodeği
    /// destekli olduğu hâlde **ses** kodeği çözülemediği için `AVPlayerItem`
    /// bir bütün olarak düşer.
    func testUnsupportedAudioIsReportedForH264WithAC3() {
        let failure = PlaybackDiagnostics.classify(
            error: avError(unsupportedFormatCode),
            timedOut: false,
            inspection: inspection(audio: ["ac-3"], video: ["avc1"]),
            extensionHint: "mp4"
        )
        guard case .unsupportedAudioCodec(let name) = failure.kind else {
            return XCTFail("ses kodeği bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(name, "AC3")
        XCTAssertTrue(
            failure.technicalCode.contains("ac-3"),
            "teşhis satırı ölçülen kodeği taşımalı: \(failure.technicalCode)"
        )
        XCTAssertTrue(
            failure.message.contains("AC3"),
            "kullanıcıya gösterilen metin kodeği adıyla söylemeli"
        )
    }

    /// Desteklenmeyen **ses** kodeği, desteklenmeyen görüntü kodeğiyle aynı
    /// anda varsa ses bildirilir: kullanıcının yapabileceği eylem aynıdır ve
    /// ses daha yaygın nedendir. Tek neden gösterilir; liste değil.
    func testAudioCodecWinsOverVideoCodec() {
        let failure = PlaybackDiagnostics.classify(
            error: nil,
            timedOut: false,
            inspection: inspection(audio: ["ec-3"], video: ["vp09"]),
            extensionHint: "mkv"
        )
        guard case .unsupportedAudioCodec(let name) = failure.kind else {
            return XCTFail("ses kodeği önce bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(name, "E-AC3")
    }

    func testUnsupportedVideoCodecIsReported() {
        let failure = PlaybackDiagnostics.classify(
            error: nil,
            timedOut: false,
            inspection: inspection(audio: ["mp4a"], video: ["av01"]),
            extensionHint: "mp4"
        )
        guard case .unsupportedVideoCodec(let name) = failure.kind else {
            return XCTFail("görüntü kodeği bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(name, "AV1")
    }

    /// Desteklenen kodekler yanlışlıkla "desteklenmiyor" diye işaretlenmemeli;
    /// aksi hâlde sağlayıcı boşuna suçlanır.
    func testSupportedCodecsAreNotFlagged() {
        let failure = PlaybackDiagnostics.classify(
            error: nil,
            timedOut: false,
            inspection: inspection(audio: ["mp4a", "twos"], video: ["avc1", "hvc1"]),
            extensionHint: "mp4"
        )
        XCTAssertEqual(failure.kind, .unknown)
        XCTAssertTrue(
            failure.technicalCode.contains("avc1"),
            "teşhis satırı ölçülen kodekleri yine göstermeli: \(failure.technicalCode)"
        )
    }

    // MARK: - Sıra

    /// Sunucu yayını reddettiğinde "kodek desteklenmiyor" denmemeli. Bu ayrım
    /// olmadan kullanıcı sağlayıcıdan gereksiz yere yeni bir sürüm ister.
    func testServerRejectionBeatsCodecConclusion() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorBadServerResponse,
            userInfo: ["HTTPStatusCode": 404]
        )
        let failure = PlaybackDiagnostics.classify(
            error: error,
            timedOut: false,
            inspection: unreadable(),
            extensionHint: "mkv"
        )
        guard case .rejected(let status) = failure.kind else {
            return XCTFail("sunucu reddi bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(status, 404)
    }

    /// Durum kodu okunamadığında yanlış bir sayı uydurulmamalı; metin kodsuz
    /// olarak gösterilir. "kod: 0" demek kullanıcıyı yanıltırdı.
    func testMissingStatusCodeDoesNotPrintZero() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)
        let failure = PlaybackDiagnostics.classify(
            error: error, timedOut: false, inspection: nil, extensionHint: "mp4"
        )
        guard case .rejected(let status) = failure.kind else {
            return XCTFail("sunucu reddi bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(status, 0)
        XCTAssertFalse(
            failure.message.contains("0"),
            "kod bulunamadıysa sayı gösterilmemeli: \(failure.message)"
        )
    }

    /// Ağ kopması ölçüm sonucundan önce gelir: sunucuya hiç ulaşılamadıysa
    /// taşıyıcı hakkında iddia yürütülemez.
    func testNetworkFailureBeatsInspection() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let failure = PlaybackDiagnostics.classify(
            error: error,
            timedOut: false,
            inspection: unreadable(),
            extensionHint: "mp4"
        )
        XCTAssertEqual(failure.kind, .offline)
    }

    /// Zaman aşımı "konteyner tanınmadı" diye bildirilmemeli: bir nedeni var
    /// (sunucu yanıt vermedi), taşıyıcı okunamamış olması yalnızca sonucudur.
    func testTimeoutBeatsUnreadableContainer() {
        let failure = PlaybackDiagnostics.classify(
            error: nil,
            timedOut: true,
            inspection: unreadable(),
            extensionHint: "mp4"
        )
        XCTAssertEqual(failure.kind, .timedOut)
    }

    /// Ölçüm hiç yapılmadıysa (`nil`) konteyner hakkında iddia yürütülmez;
    /// kanıtsız bir suçlama kullanıcıyı yanlış yöne gönderir.
    func testNoInspectionDoesNotClaimUnrecognizedContainer() {
        let failure = PlaybackDiagnostics.classify(
            error: nil, timedOut: false, inspection: nil, extensionHint: "mkv"
        )
        XCTAssertEqual(failure.kind, .unknown)
    }

    /// Taşıyıcı gerçekten okunamadıysa bu açıkça bildirilir ve ölçülen uzantı
    /// mesaja girer.
    func testUnreadableContainerIsReportedWithExtension() {
        let failure = PlaybackDiagnostics.classify(
            error: nil, timedOut: false, inspection: unreadable(), extensionHint: "mkv"
        )
        guard case .unrecognizedContainer(let hint) = failure.kind else {
            return XCTFail("konteyner bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(hint, "mkv")
        XCTAssertTrue(failure.message.contains("mkv"), failure.message)
    }

    /// Konteyner nedeninin uzantısı `AVFoundation` hatasından gelirse boş
    /// kalabilir; asıl çağrıdaki uzantı tamamlanmalı ki mesajda "()" görünmesin.
    func testContainerReasonReceivesExtensionHintWhenMissing() {
        let failure = PlaybackDiagnostics.classify(
            error: avError(containerCode),
            timedOut: false,
            inspection: nil,
            extensionHint: "avi"
        )
        guard case .unrecognizedContainer(let hint) = failure.kind else {
            return XCTFail("konteyner bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(hint, "avi")
        XCTAssertTrue(failure.message.contains("avi"), failure.message)
    }

    /// Kimlik reddi ayrı bildirilir: kullanıcının eylemi farklıdır (hesabını
    /// kontrol eder, sağlayıcıya başka bir biçim sormaz).
    func testUnauthorizedIsReportedSeparately() {
        let failure = PlaybackDiagnostics.classify(
            error: avError(unauthorizedCode),
            timedOut: false,
            inspection: nil,
            extensionHint: "mp4"
        )
        XCTAssertEqual(failure.kind, .unauthorized)
    }

    // MARK: - Hata zinciri

    /// Gerçek HTTP kodu çoğu zaman yalnızca alt hata zincirinde görünür:
    /// `AVFoundation` üst hatayı "-11800 bilinmeyen" diye sarmalar.
    func testStatusCodeIsReadFromUnderlyingErrorChain() {
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorBadServerResponse,
            userInfo: ["HTTPStatusCode": 503]
        )
        let top = NSError(
            domain: AVFoundationErrorDomain,
            code: unsupportedFormatCode,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        let failure = PlaybackDiagnostics.classify(
            error: top, timedOut: false, inspection: nil, extensionHint: "mp4"
        )
        guard case .rejected(let status) = failure.kind else {
            return XCTFail("sunucu reddi bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(status, 503)
    }

    /// Teşhis satırı dile bağlı olmamalı: kullanıcı bunu sağlayıcıya iletebilir.
    /// Bu yüzden `localizedDescription` değil, alan adı + kod gösterilir.
    func testTechnicalCodeUsesDomainAndNumberNotLocalizedText() {
        let failure = PlaybackDiagnostics.classify(
            error: avError(unsupportedFormatCode),
            timedOut: false,
            inspection: nil,
            extensionHint: "mp4"
        )
        XCTAssertTrue(
            failure.technicalCode.contains("\(unsupportedFormatCode)"),
            failure.technicalCode
        )
    }

    /// Kanıt hiç yoksa bile teşhis satırı boş bırakılmaz; "hiçbir şey yok"
    /// demek kullanıcıya tekrar bildirmekten başka yol bırakmaz.
    func testTechnicalCodeIsNeverEmpty() {
        let failure = PlaybackDiagnostics.classify(
            error: nil, timedOut: false, inspection: nil, extensionHint: ""
        )
        XCTAssertFalse(failure.technicalCode.isEmpty)
        XCTAssertEqual(failure.kind, .unknown)
    }

    // MARK: - Metin

    /// Kullanıcıya gösterilen metin ham anahtar olmamalı.
    func testMessagesAreLocalizedNotKeys() {
        let kinds: [PlaybackFailureKind] = [
            .unsupportedAudioCodec(name: "AC3"),
            .unsupportedVideoCodec(name: "AV1"),
            .unrecognizedContainer(extensionHint: "mkv"),
            .rejected(status: 404),
            .unauthorized,
            .offline,
            .timedOut,
            .unknown,
        ]
        for kind in kinds {
            let message = PlaybackFailure(kind: kind, technicalCode: "X").message
            XCTAssertFalse(message.isEmpty, "\(kind) metni boş olmamalı")
            XCTAssertFalse(
                message.hasPrefix("player.error"),
                "\(kind) için yerelleştirme anahtarı çözülememiş: \(message)"
            )
            XCTAssertFalse(
                message.hasPrefix("error."),
                "\(kind) için yerelleştirme anahtarı çözülememiş: \(message)"
            )
        }
    }

    /// Biçimlendirmeli anahtarlarda yer tutucu gerçekten doldurulmalı.
    func testFormatPlaceholdersAreSubstituted() {
        let message = PlaybackFailure(
            kind: .rejected(status: 403), technicalCode: "X"
        ).message
        XCTAssertTrue(message.contains("403"), message)
        XCTAssertFalse(message.contains("%d"), message)
    }

    /// Teşhis satırı açıklamanın altına eklenir ve açıklama kaybolmaz.
    func testFullMessageKeepsDescriptionAndAppendsDiagnostics() {
        let failure = PlaybackFailure(
            kind: .unsupportedAudioCodec(name: "AC3"),
            technicalCode: "AVFoundationErrorDomain -11800 ← ac-3"
        )
        XCTAssertTrue(failure.fullMessage.contains("AC3"))
        XCTAssertTrue(failure.fullMessage.contains("-11800"))
        XCTAssertNotEqual(failure.fullMessage, failure.message)
    }

    // MARK: - Yardımcılar

    /// Dört harfli kodek kimliği okunabilir metne çevrilmeli.
    func testFourCCDecodesCodecIdentifiers() {
        XCTAssertEqual(PlaybackDiagnostics.fourCC(0x6163_2D33), "ac-3")
        XCTAssertEqual(PlaybackDiagnostics.fourCC(0x6D70_3461), "mp4a")
    }

    /// Yazdırılamayan baytlar çöp karakter olarak sızmamalı; teşhis satırı
    /// terminalde ve hata raporunda okunabilir kalmalıdır.
    ///
    /// Beklenen uzunluk **dört**: `fourCC` her zaman dört baytı çözer, bayt
    /// başına bir karakter üretir. İlk yazımda üç `?` beklenmişti ve test
    /// düşmüştü — derleme bozuk olduğu için test o güne kadar hiç
    /// çalışmamıştı, bu yüzden hata ancak CI derlemesi düzelince göründü.
    func testFourCCSanitizesNonPrintableBytes() {
        let decoded = PlaybackDiagnostics.fourCC(0x0000_0001)
        XCTAssertEqual(decoded, "????")
        XCTAssertEqual(decoded.count, 4, "dört bayt, dört karakter")
        XCTAssertFalse(decoded.contains("\u{0}"))
    }

    /// Teşhis ölçümü oynatıcıyla **aynı** User-Agent'ı göndermelidir; farklı
    /// bir ad gönderilseydi "sunucu uygulamayı engelliyor" teşhisi yanlış çıkardı.
    func testInspectionUsesSameUserAgentAsPlayback() {
        XCTAssertEqual(PlaybackDiagnostics.userAgent, "IPiOS/1.0 (iOS)")
        XCTAssertEqual(
            PlaybackDiagnostics.headerFieldsKey,
            "AVURLAssetHTTPHeaderFieldsKey"
        )
    }
}
