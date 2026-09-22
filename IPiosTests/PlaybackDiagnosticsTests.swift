import XCTest
@testable import IPiOS

/// Oynatma hatası sınıflandırmasının kurallarını doğrular.
///
/// Neden gerekli: üç tur boyunca kullanıcı yalnızca "Oynatma başlatılamadı."
/// cümlesini gördü ve sorun teşhis edilemedi. Bu cümle birbirinden tamamen
/// farklı kusurları aynı metne indiriyordu: çözülemeyen bir kodek, tanınmayan
/// bir konteyner ve sunucunun yayını reddetmesi. Sınıflandırma yanlış sırayla
/// yapılırsa kullanıcıya **yanlış** neden gösterilir — örneğin sunucu 404
/// dönerken "kodek desteklenmiyor" denir ve kullanıcı boşuna sağlayıcıdan
/// başka bir sürüm ister. Bu yüzden sıra teste bağlanmıştır.
///
/// `AVPlayer` döneminde bu dosya `AVError` kodlarını ve `AVURLAsset` ile
/// yapılan akış ölçümünü sınıyordu. Oynatma çekirdeği libvlc'ye taşındığı için
/// **kanıt kaynağı değişti**: hüküm artık libvlc'nin kendi günlüğünden okunur.
/// Testler de bu yeni kanıt kaynağına göre yazılmıştır.
final class PlaybackDiagnosticsTests: XCTestCase {

    // MARK: - Yardımcılar

    private func profile(audio: [String] = [], video: [String] = []) -> VLCStreamProfile {
        VLCStreamProfile(audioCodecs: audio, videoCodecs: video)
    }

    private func classify(
        _ logLines: [String],
        profile streamProfile: VLCStreamProfile? = nil,
        extensionHint: String = "mkv",
        timedOut: Bool = false
    ) -> PlaybackFailure {
        VLCDiagnostics.classify(
            profile: streamProfile,
            logLines: logLines,
            extensionHint: extensionHint,
            timedOut: timedOut
        )
    }

    // MARK: - Sunucu tarafı (en kesin kanıt, ilk sırada)

    /// Sunucu reddi kodek sorunundan **önce** gelir: sunucu yayını vermediyse
    /// kodek hakkında hüküm verilemez.
    func testHTTPErrorIsRejectedBeforeCodecVerdict() {
        let failure = classify(
            ["access error: HTTP 404 Not Found"],
            profile: profile(audio: ["ac-3"])
        )
        XCTAssertEqual(failure.kind, .rejected(status: 404))
        XCTAssertEqual(failure.technicalCode, "HTTP 404")
    }

    /// Kimlik reddi ayrı bildirilir: kullanıcının eylemi farklıdır (hesabını
    /// kontrol eder, sağlayıcıya başka bir biçim sormaz).
    func testUnauthorizedIsReportedSeparately() {
        let failure = classify(["access error: HTTP 403 Forbidden"])
        XCTAssertEqual(failure.kind, .unauthorized)
        XCTAssertEqual(failure.technicalCode, "HTTP 403")
    }

    /// Durum kodu okunamayan bir reddin metni "kod: 0" içermemeli; bu kullanıcıyı
    /// yanıltırdı.
    func testHTTP500IsReportedWithStatus() {
        let failure = classify(["access error: HTTP 503 Service Unavailable"])
        XCTAssertEqual(failure.kind, .rejected(status: 503))
    }

    /// Günlükteki sayısal gürültü durum kodu sanılmamalı.
    func testNonHTTPNumbersAreNotReadAsStatusCodes() {
        let failure = classify(
            ["main error: buffer deadlock prevented (value 404)"]
        )
        XCTAssertEqual(failure.kind, .unknown)
    }

    /// Bazı paneller durum kodunu düz metinle bildirir.
    func testAccessDeniedPhraseIsTreatedAsUnauthorized() {
        let failure = classify(["access error: access denied for this account"])
        XCTAssertEqual(failure.kind, .unauthorized)
    }

    // MARK: - Ağ katmanı

    func testTimeoutIsReportedAsSuch() {
        let failure = classify(["http error: connection timed out"])
        XCTAssertEqual(failure.kind, .timedOut)
    }

    /// Süre aşımı hatasız geldiğinde de (libvlc satır yazmadan bekleyebilir)
    /// bayrak üzerinden bildirilmelidir.
    func testTimeoutFlagAloneIsEnough() {
        let failure = classify([], timedOut: true)
        XCTAssertEqual(failure.kind, .timedOut)
    }

    func testConnectionRefusedIsReportedAsOffline() {
        let failure = classify(["tcp error: could not connect to server"])
        XCTAssertEqual(failure.kind, .offline)
    }

    // MARK: - Ses kodeği: artık kanıt isteyen hüküm

    /// **Bu testin koruduğu davranış, VLC geçişinin en kritik düzeltmesidir.**
    ///
    /// `AVPlayer` döneminde AC3 görülmesi tek başına "çalınamaz" hükmüydü.
    /// libvlc AC3'ü yazılım çözücüsüyle oynatır; aynı tabloyu hüküm olarak
    /// kullanmak kullanıcıya **yanlış** bir neden gösterirdi ("sağlayıcıdan AAC
    /// isteyin") ve asıl sorun görünmez kalırdı. Bu yüzden kodeğin ölçülmüş
    /// olması yetmez: libvlc'nin şikâyet etmesi gerekir.
    func testMeasuredAudioCodecAloneDoesNotProduceCodecVerdict() {
        let failure = classify([], profile: profile(audio: ["ac-3"], video: ["H264"]))
        XCTAssertEqual(
            failure.kind,
            .unknown,
            "kodek ölçümü tek başına hüküm vermemeli"
        )
    }

    /// Kanıt varsa hüküm verilir ve kodek adı kullanıcıya söylenir.
    func testAudioCodecFailureWithLogEvidenceIsReported() {
        let failure = classify(
            ["main decoder error: no suitable audio decoder for ac-3"],
            profile: profile(audio: ["ac-3"], video: ["H264"])
        )
        guard case .unsupportedAudioCodec(let name) = failure.kind else {
            return XCTFail("ses kodeği bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(name, "AC3")
        // Teşhis satırı hem ölçümü hem kanıtı taşımalı: kullanıcı hangi kodekten
        // söz edildiğini ve libvlc'nin ne dediğini görebilsin.
        XCTAssertTrue(failure.technicalCode.contains("AC3"), failure.technicalCode)
        XCTAssertTrue(
            failure.technicalCode.contains("no suitable audio decoder"),
            failure.technicalCode
        )
    }

    /// Kodek adı geçiyor ama günlük onu **başarıyla** açtığını söylüyorsa hüküm
    /// verilmemelidir: "using audio decoder" bir sorun bildirimi değildir.
    func testCodecMentionedAsWorkingIsNotAFailure() {
        let failure = classify(
            ["main debug: using audio decoder module \"avcodec\""],
            profile: profile(audio: ["eac3"], video: ["H264"])
        )
        XCTAssertEqual(failure.kind, .unknown)
    }

    /// E-AC3'ün iki yazımı (`eac3`, `ec-3`) da aynı adı üretmeli; kullanıcıya
    /// iki farklı kodek varmış izlenimi verilmemeli.
    func testEAC3SpellingsMapToSameName() {
        for spelling in ["eac3", "ec-3"] {
            let failure = classify(
                ["main decoder error: failed to create audio decoder for \(spelling)"],
                profile: profile(audio: [spelling])
            )
            guard case .unsupportedAudioCodec(let name) = failure.kind else {
                return XCTFail("\(spelling) için hüküm bekleniyordu")
            }
            XCTAssertEqual(name, "E-AC3")
        }
    }

    /// DTS'in profili biliniyorsa aile adı değil, **kesin** ad söylenmeli:
    /// sağlayıcıdan istenecek şey profille değişir.
    func testDTSProfileIsRefinedWhenKnown() {
        let failure = classify(
            ["main decoder error: failed to decode audio (dts-hd)"],
            profile: profile(audio: ["dts-hd"])
        )
        guard case .unsupportedAudioCodec(let name) = failure.kind else {
            return XCTFail("DTS-HD için hüküm bekleniyordu")
        }
        XCTAssertEqual(name, "DTS-HD")
    }

    /// Tanınmayan bir DTS varyantında genel ad bırakılır. Yanlış bir sürüm adı
    /// söylemek, genel ad söylemekten kötüdür.
    func testUnknownDTSVariantFallsBackToFamilyName() {
        let failure = classify(
            ["main decoder error: failed to decode audio (dts)"],
            profile: profile(audio: ["dts"])
        )
        guard case .unsupportedAudioCodec(let name) = failure.kind else {
            return XCTFail("DTS için hüküm bekleniyordu")
        }
        XCTAssertEqual(name, "DTS")
    }

    // MARK: - Konteyner

    /// libvlc demuxer bulamadığını söylediğinde uzantı da bildirilir; kullanıcı
    /// hangi dosyanın açılmadığını görebilsin.
    func testUnknownDemuxerIsReportedWithExtension() {
        let failure = classify(
            ["main error: no suitable demux module for this input"],
            extensionHint: "mkv"
        )
        guard case .unrecognizedContainer(let hint) = failure.kind else {
            return XCTFail("konteyner bildirilmeliydi, gelen: \(failure.kind)")
        }
        XCTAssertEqual(hint, "mkv")
        XCTAssertTrue(failure.message.contains("mkv"), failure.message)
    }

    func testCannotRecognizePhraseIsReportedAsContainer() {
        let failure = classify(
            ["main error: cannot recognize the file format"],
            extensionHint: "avi"
        )
        guard case .unrecognizedContainer = failure.kind else {
            return XCTFail("konteyner bekleniyordu, gelen: \(failure.kind)")
        }
    }

    /// Uzantı elde edilemediğinde metinde boş parantez görünmemeli; tire konur.
    func testEmptyExtensionRendersPlaceholderInsteadOfEmptyParentheses() {
        let failure = classify(
            ["main error: no suitable demux module"],
            extensionHint: ""
        )
        XCTAssertFalse(failure.message.contains("()"), failure.message)
    }

    // MARK: - Kesilme (başladıktan sonra)

    /// Yayın **başladıktan sonra** kesildiğinde "başlatılamadı" demek yanlış
    /// olurdu: yayın açılmıştı. Ayırt edilebilen neden yoksa "kesildi" denir.
    func testInterruptionWithoutEvidenceIsReportedAsInterrupted() {
        let failure = VLCDiagnostics.classifyInterruption(
            logLines: ["main debug: nothing notable here"]
        )
        XCTAssertEqual(failure.kind, .interrupted)
    }

    /// Kesilmenin **nedeni** ayırt edilebiliyorsa o gösterilir: kullanıcının
    /// yapacağı şey nedene göre değişir.
    func testInterruptionWithServerRefusalKeepsRealReason() {
        let failure = VLCDiagnostics.classifyInterruption(
            logLines: ["access error: HTTP 403 Forbidden"]
        )
        XCTAssertEqual(failure.kind, .unauthorized)
    }

    /// Zaman aşımı ve ağ kopması kesilme sırasında da "kesildi" olarak
    /// bildirilir; nedeni teknik satırda korunur.
    func testInterruptionFromTimeoutIsReportedAsInterrupted() {
        let failure = VLCDiagnostics.classifyInterruption(
            logLines: ["http error: connection timed out"]
        )
        XCTAssertEqual(failure.kind, .interrupted)
        XCTAssertTrue(
            failure.technicalCode.contains("timed out"),
            failure.technicalCode
        )
    }

    // MARK: - Ölçüm özeti

    /// Teşhis satırı dile bağlı olmayan kodek kodları taşımalı: İngilizce hata
    /// metinleri Türkçe arayüzde gürültüdür, kodek adları ise aranabilir.
    func testTechnicalSummaryListsVideoThenAudio() {
        let summary = profile(audio: ["AC-3 audio"], video: ["H264"]).technicalSummary
        XCTAssertTrue(summary.contains("V:H264"), summary)
        XCTAssertTrue(summary.contains("A:AC-3 audio"), summary)
    }

    /// Ölçüm hiç yapılmadıysa özet boş olmalı; "V: A:" artığı bırakılmamalı.
    func testEmptyProfileHasEmptySummary() {
        XCTAssertTrue(profile().technicalSummary.isEmpty)
    }

    /// Kodek tablosunda olmayan bir ses kodeği ad üretmemeli, ama hata da
    /// vermemeli: tanınmayan kodek bir sorun değildir, yalnızca adlandırılamaz.
    func testUnknownCodecProducesNoName() {
        XCTAssertNil(profile(audio: ["Some Exotic Codec"]).audioBurdenedName)
    }

    // MARK: - Mesajlar

    /// Teşhis kodu boşsa metinde "Teknik: " artığı bırakılmamalı.
    func testEmptyTechnicalCodeDoesNotLeaveTrailingLabel() {
        let failure = PlaybackFailure(kind: .unknown, technicalCode: "")
        XCTAssertEqual(failure.fullMessage, failure.message)
        XCTAssertFalse(failure.fullMessage.contains("Teknik"))
    }

    /// Teşhis kodu varsa açıklamanın ardına eklenir.
    func testTechnicalCodeIsAppendedToMessage() {
        let failure = PlaybackFailure(kind: .unknown, technicalCode: "V:H264 A:AC3")
        XCTAssertTrue(failure.fullMessage.contains("V:H264 A:AC3"), failure.fullMessage)
    }
}
