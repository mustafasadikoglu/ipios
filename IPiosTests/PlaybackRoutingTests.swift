import XCTest
@testable import IPiOS

/// Oynatma adresi seçiminin ve Xtream uzantı normalleştirmesinin kurallarını
/// doğrular.
///
/// Neden gerekli: canlı yayınların oynatılmamasının kök nedeni bu iki kuraldı.
/// Xtream panelleri canlı yayın için `stream_type = "ts"` bildirir ve
/// `/live/<user>/<pass>/<id>.ts` ham bir MPEG-TS akışıdır; `AVPlayer` bu
/// konteyneri çözemez ve hata vermeden siyah ekranda kalır. Yalnızca HLS
/// paketlemesi (`.m3u8`) oynatılabilir. Bu kurallar sessizce geri alınırsa
/// kusur yeniden ortaya çıkar ve yalnızca gerçek bir sağlayıcıyla denenerek
/// fark edilebilir.
final class PlaybackRoutingTests: XCTestCase {

    // MARK: - Yardımcılar

    /// Testte sahte bir tip yazmak yerine üretimdeki `AnyMediaItem` kullanılır:
    /// `playbackCandidates` gerçekte bu tipi görür, dolayısıyla adres üretimi
    /// sırasında tip kaynaklı bir sapma da bu testte ortaya çıkar.
    private func item(_ url: String) -> AnyMediaItem {
        AnyMediaItem(
            id: "1",
            title: "Örnek",
            imageURL: nil,
            streamURL: URL(string: url)!,
            sourceID: UUID(),
            kind: .live
        )
    }

    private let base = "http://cdn.example.com/live/user/pass/123"

    // MARK: - Aday sırası

    /// Canlı yayında HLS birincil, ham TS yedek olmalı.
    @MainActor
    func testLiveCandidatesPreferHLSThenTS() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("\(base).m3u8"), isLive: true
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            ["\(base).m3u8", "\(base).ts"],
            "Canlı yayında önce HLS denenmeli, ham TS yalnızca yedek olmalı"
        )
    }

    /// Kaynak `.ts` bildirse bile HLS önce denenmeli: asıl kusur buydu.
    @MainActor
    func testLiveCandidatesLiftRawTransportStreamToHLS() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("\(base).ts"), isLive: true
        )
        XCTAssertEqual(candidates.first?.absoluteString, "\(base).m3u8")
        XCTAssertEqual(candidates.count, 2)
    }

    /// VOD'da doğrudan oynatılabilen konteynerler tek adayla denenir; uzantı
    /// değiştirilmez (`.mp4` doğrudan oynatılabilir ve yedek adres üretmek
    /// sağlayıcıya boşuna istek göndermek olurdu).
    @MainActor
    func testPlayableVODContainerUsesSingleCandidate() {
        for ext in ["mp4", "mov", "m2ts"] {
            let url = "http://cdn.example.com/movie/user/pass/9.\(ext)"
            let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
            XCTAssertEqual(candidates.map(\.absoluteString), [url], "\(ext) tek aday olmalı")
        }
    }

    /// `AVPlayer`'ın çözemediği konteynerlerde (`.mkv`, `.avi`) HLS yedeği
    /// denenmeli: aksi halde oynatma hiç başlamaz ve kullanıcı nedensiz hata
    /// görür. Asıl adres yine ilk sırada kalır, çünkü sağlayıcı konteyneri
    /// destekliyorsa gereksiz istek gönderilmemelidir.
    @MainActor
    func testUnplayableVODContainerFallsBackToHLS() {
        for ext in ["mkv", "avi", "webm", "flv", "wmv"] {
            let url = "http://cdn.example.com/movie/user/pass/9.\(ext)"
            let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
            XCTAssertEqual(
                candidates.map(\.absoluteString),
                [url, "http://cdn.example.com/movie/user/pass/9.m3u8"],
                "\(ext) için asıl adres önce, HLS yedek sonra denenmeli"
            )
        }
    }

    /// Uzantısız adres için uydurma adres üretilmemeli.
    @MainActor
    func testCandidatesFallBackToPrimaryWhenExtensionIsMissing() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("\(base)"), isLive: true
        )
        XCTAssertEqual(candidates.map(\.absoluteString), [base])
    }

    /// Sorgu dizesi (jeton, oturum kimliği) korunmalı; düşerse sağlayıcı
    /// isteği reddeder.
    @MainActor
    func testCandidatesPreserveQueryString() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("\(base).m3u8?token=abc"), isLive: true
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            ["\(base).m3u8?token=abc", "\(base).ts?token=abc"]
        )
    }

    // MARK: - Xtream uzantı normalleştirmesi

    /// `ts` bilinçli olarak `m3u8`'e çevrilir; `AVPlayer` ham TS'i çözemez.
    func testTransportStreamHintNormalizesToHLS() {
        XCTAssertEqual(XtreamClient.normalizeExtension("ts"), "m3u8")
        XCTAssertEqual(XtreamClient.normalizeExtension("mpegts"), "m3u8")
        XCTAssertEqual(XtreamClient.normalizeExtension("m3u8"), "m3u8")
        XCTAssertEqual(XtreamClient.normalizeExtension("HLS"), "m3u8")
    }

    /// Oynatılabilir VOD uzantıları olduğu gibi kalmalı ve **HLS'e
    /// çevrilmemeli**. Bu kural bir kez bozulmuştu: normalleştirme tüm
    /// adresleri HLS'e zorluyordu, böylece film/dizi adresleri sağlayıcının
    /// sunmadığı bir yola dönüşüyor ve oynatma hiç başlamıyordu.
    func testVideoContainersArePreserved() {
        for ext in ["mp4", "mkv", "avi", "mov", "webm", "m2ts"] {
            XCTAssertEqual(XtreamClient.normalizeExtension(ext), ext, "\(ext) korunmalı")
        }
    }

    /// Uzantı bildirilmezse HLS varsayılır (güvenli taraf).
    func testMissingHintDefaultsToHLS() {
        XCTAssertEqual(XtreamClient.normalizeExtension(nil), "m3u8")
        XCTAssertEqual(XtreamClient.normalizeExtension(""), "m3u8")
    }

    /// Baştaki nokta temizlenir; `".mp4"` adres içinde `..mp4` üretmemeli.
    func testLeadingDotIsStripped() {
        XCTAssertEqual(XtreamClient.normalizeExtension(".mp4"), "mp4")
    }
}
