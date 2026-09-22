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

    /// VOD'da asıl adres **her zaman** ilk sırada denenir; sağlayıcının
    /// bildirdiği biçim destekleniyorsa ona öncelik verilir.
    @MainActor
    func testVODAlwaysTriesDeclaredAddressFirst() {
        for ext in ["mp4", "mov", "m2ts", "mkv", "avi", "webm"] {
            let url = "http://cdn.example.com/movie/user/pass/9.\(ext)"
            let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
            XCTAssertEqual(candidates.first?.absoluteString, url, "\(ext) ilk aday olmalı")
        }
    }

    /// `mp4` her durumda denenir: Xtream VOD'un standart biçimidir ve
    /// sağlayıcı `container_extension` alanında farklı bir şey bildirse bile
    /// dosya çoğu zaman `.mp4` olarak da çalışır.
    @MainActor
    func testVODAlwaysIncludesMP4Candidate() {
        for ext in ["mkv", "avi", "webm", "m2ts", "mov", "flv", "wmv"] {
            let url = "http://cdn.example.com/movie/user/pass/9.\(ext)"
            let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
            XCTAssertTrue(
                candidates.contains { $0.pathExtension == "mp4" },
                "\(ext) için mp4 yedeği bulunmalı"
            )
        }
    }

    /// mp4 zaten asıl adresteyse yedek olarak **tekrar eklenmemeli**.
    @MainActor
    func testVODDoesNotDuplicateMP4WhenItIsPrimary() {
        let url = "http://cdn.example.com/movie/user/pass/9.mp4"
        let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
        XCTAssertEqual(
            candidates.filter { $0.pathExtension == "mp4" }.count,
            1,
            "asıl adres mp4 ise ikinci kez eklenmemeli"
        )
    }

    /// VOD'da HLS **en son** çare olarak denenir.
    ///
    /// Xtream VOD'u standart olarak HLS ile sunmaz; bu yüzden `.m3u8` birincil
    /// yedek değildir. Ancak VOD'u HLS olarak da paketleyen paneller vardır ve
    /// bir deneme daha yapmak, kullanıcıya kesin bir hata göstermekten iyidir.
    @MainActor
    func testVODTriesHLSAsLastResortOnly() {
        let url = "http://cdn.example.com/movie/user/pass/9.mkv"
        let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            [
                url,
                "http://cdn.example.com/movie/user/pass/9.mp4",
                "http://cdn.example.com/movie/user/pass/9.m3u8"
            ],
            "sıra: asıl → mp4 → m3u8 olmalı"
        )
    }

    /// VOD'da tek adayla yetinilmemeli: "canlı çalışıyor, film/dizi
    /// çalışmıyor" farkının kök nedeni buydu.
    ///
    /// Canlı yayında uzantıdan bağımsız olarak her zaman iki aday üretilir ve
    /// biri tutmazsa diğeri denenir. VOD'da yedek yalnızca çözülemeyen
    /// konteynerlerde üretiliyordu; sağlayıcı oynatılabilir görünen bir uzantı
    /// bildirdiğinde liste tek elemana düşüyor ve o adres tutmazsa kullanıcı
    /// doğrudan hata uyarısı görüyordu.
    @MainActor
    func testVODNeverReliesOnASingleCandidate() {
        for ext in ["mp4", "mov", "m2ts", "mkv", "avi", "webm", "flv"] {
            let url = "http://cdn.example.com/movie/user/pass/9.\(ext)"
            let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
            XCTAssertGreaterThan(
                candidates.count, 1,
                "\(ext) için yedek aday üretilmeli — tek adayla kalınmamalı"
            )
        }
    }

    /// Sorgu dizesi yedek adreslere de taşınmalı; düşerse sağlayıcı isteği
    /// reddeder.
    @MainActor
    func testVODFallbackPreservesQueryString() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("http://cdn.example.com/movie/user/pass/9.mkv?token=abc"),
            isLive: false
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            [
                "http://cdn.example.com/movie/user/pass/9.mkv?token=abc",
                "http://cdn.example.com/movie/user/pass/9.mp4?token=abc",
                "http://cdn.example.com/movie/user/pass/9.m3u8?token=abc"
            ]
        )
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
