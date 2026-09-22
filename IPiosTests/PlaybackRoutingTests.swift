import XCTest
@testable import IPiOS

/// Oynatma adresi seçiminin ve Xtream uzantı normalleştirmesinin kurallarını
/// doğrular.
///
/// Neden gerekli: kullanıcının bildirdiği "filmler çalışmıyor" kusurunun kök
/// nedeni sağlayıcının VOD'u **yalnızca Matroska (.mkv)** olarak sunması ve
/// `AVFoundation`'ın Matroska demuxer'ının olmamasıydı. Bu yüzden oynatma
/// çekirdeği libvlc'ye taşındı. Aday listesi bu geçişte **kasıtlı olarak
/// kısaldı**: uzantıyı değiştirip yedek adres denemek artık gecikmeden başka
/// bir şey üretmiyor, çünkü ölçüm sunucunun `.mkv` dışındaki uzantılarda
/// gövdeyi **boş** döndürdüğünü gösterdi (bkz. `scripts/xtream_teshis.py`).
/// Bu kurallar sessizce geri alınırsa kusur yeniden ortaya çıkar ve yalnızca
/// gerçek bir sağlayıcıyla denenerek fark edilebilir.
final class PlaybackRoutingTests: XCTestCase {

    // MARK: - Yardımcılar

    /// Testte sahte bir tip yazmak yerine üretimdeki `AnyMediaItem` kullanılır:
    /// `playbackCandidates` gerçekte bu tipi görür, dolayısıyla adres üretimi
    /// sırasında tip kaynaklı bir sapma da bu testte ortaya çıkar.
    private func item(_ url: String, kind: CategoryKind = .live) -> AnyMediaItem {
        AnyMediaItem(
            id: "1",
            title: "Örnek",
            imageURL: nil,
            streamURL: URL(string: url)!,
            sourceID: UUID(),
            kind: kind
        )
    }

    private let base = "http://cdn.example.com/live/user/pass/123"
    private let vodBase = "http://cdn.example.com/movie/user/pass/456"

    // MARK: - Canlı yayın

    /// Canlı yayında asıl adres korunur; HLS ve ham TS sırayla yedek olur.
    ///
    /// İkisi de denenir çünkü libvlc ham MPEG-TS'i de HLS'i de çözer — hangisini
    /// sunacağını sağlayıcı belirler ve önceden bilinemez.
    @MainActor
    func testLiveCandidatesKeepPrimaryThenTryBothCarriers() {
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item("\(base).m3u8"), isLive: true
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            ["\(base).m3u8", "\(base).ts"]
        )
    }

    /// Asıl adres ham TS olsa bile HLS yedek olarak denenir.
    @MainActor
    func testLiveCandidatesFromTSIncludeHLS() {
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item("\(base).ts"), isLive: true
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            ["\(base).ts", "\(base).m3u8"]
        )
    }

    /// Uzantısız adreste türetilecek yedek yoktur; asıl adres tek aday kalır.
    @MainActor
    func testLiveCandidatesWithoutExtensionKeepPrimaryOnly() {
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item(base), isLive: true
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.absoluteString, base)
    }

    // MARK: - VOD / dizi

    /// **Kök nedeni kapatan test.** Sağlayıcı VOD'u `.mkv` olarak sunar ve
    /// libvlc bu konteyneri doğrudan çözer; asıl adres listenin **başında**
    /// olmalıdır. Sıra değişirse kullanıcı her filmde önce çalışmayan bir
    /// yedek adresi beklemek zorunda kalır.
    @MainActor
    func testVODPrimaryMatroskaIsFirstCandidate() {
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item("\(vodBase).mkv", kind: .movie), isLive: false
        )
        XCTAssertEqual(candidates.first?.pathExtension, "mkv")
        XCTAssertEqual(candidates.first?.absoluteString, "\(vodBase).mkv")
    }

    /// VOD'da `.m3u8` yedeği **üretilmez**: VOD'un HLS olarak paketlendiği bir
    /// panel bu sağlayıcıda gözlenmedi ve her yedek deneme zaman aşımına kadar
    /// bekleyip kullanıcıya gecikme olarak yansıyor.
    @MainActor
    func testVODCandidatesDoNotIncludeHLSFallback() {
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item("\(vodBase).mkv", kind: .movie), isLive: false
        )
        XCTAssertFalse(
            candidates.contains { $0.pathExtension == "m3u8" },
            "VOD adaylarında HLS olmamalı: \(candidates)"
        )
    }

    /// `.mp4` yedeği korunur: azınlıkta da olsa VOD'u H.264/MP4 sunan paneller
    /// vardır ve bir deneme daha yapmak kesin hata göstermekten iyidir.
    @MainActor
    func testVODCandidatesIncludeMP4FallbackAfterPrimary() {
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item("\(vodBase).mkv", kind: .movie), isLive: false
        )
        XCTAssertEqual(
            candidates.map(\.pathExtension),
            ["mkv", "mp4"]
        )
    }

    /// Asıl adres zaten `.mp4` ise kendini yineleyen bir yedek üretilmez.
    @MainActor
    func testVODCandidatesDoNotDuplicateMP4() {
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item("\(vodBase).mp4", kind: .movie), isLive: false
        )
        XCTAssertEqual(candidates.count, 1)
    }

    /// Asıl adres zaten `.m3u8` ise `.mp4` yedeği eklenir; aksi hâlde listenin
    /// tamamı tek bir adresten ibaret kalırdı.
    @MainActor
    func testVODCandidatesFromHLSStillGetMP4Fallback() {
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item("\(vodBase).m3u8", kind: .movie), isLive: false
        )
        XCTAssertEqual(candidates.map(\.pathExtension), ["m3u8", "mp4"])
    }

    // MARK: - Uzantı değiştirme güvenliği

    /// Şifresinde eğik çizgi bulunan bir kullanıcıda yolun bozulmaması gerekir.
    ///
    /// Ölçülmüş kusur: eski kod `url.path` (çözülmüş) alıp `components.path`
    /// ayarlayıcısına veriyordu; o ayarlayıcı `/` karakterini kodlamaz. Asıl
    /// adreste `%2F` olarak kodlanmış karakter çözülüp ham `/` olarak geri
    /// yazılıyor, yol bir fazla parçaya bölünüyor ve kimlik bilgisi yanlış
    /// okunuyordu. Belirti sinsiydi: **yalnızca yedek adres** bozulur, asıl
    /// adres doğru kalır — yani kimi film açılır, kimi açılmaz.
    @MainActor
    func testExtensionReplacementPreservesEncodedSlash() {
        let url = "http://cdn.example.com/movie/user/pa%2Fss/456.mkv"
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item(url, kind: .movie), isLive: false
        )

        guard candidates.count == 2 else {
            return XCTFail("iki aday bekleniyordu, gelen: \(candidates)")
        }
        let fallback = candidates[1].absoluteString
        XCTAssertTrue(
            fallback.contains("pa%2Fss"),
            "yedek adreste kodlanmış eğik çizgi korunmalıydı: \(fallback)"
        )
        XCTAssertFalse(
            fallback.contains("/pa/ss/"),
            "kimlik bilgisi yol parçalarına bölünmemeliydi: \(fallback)"
        )
    }

    /// Uzantı son yol parçası içinde aranmalı; üst dizinlerdeki noktalar
    /// (`/a.b/456`) uzantı sanılmamalıdır.
    @MainActor
    func testExtensionIsNotReadFromParentDirectories() {
        let url = "http://cdn.example.com/a.b/user/pass/456"
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item(url, kind: .movie), isLive: false
        )
        // Uzantı yok: türetilecek yedek adres de yoktur, asıl adres korunur.
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.absoluteString, url)
    }

    /// Nokta ile **başlayan** son parça (gizli dosya benzeri) uzantı sayılmaz;
    /// aksi hâlde `/456.` gibi bir adres tümüyle değiştirilerek bozulurdu.
    @MainActor
    func testLeadingDotInLastSegmentIsNotAnExtension() {
        let url = "http://cdn.example.com/movie/user/pass/.hidden"
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item(url, kind: .movie), isLive: false
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.absoluteString, url)
    }

    /// Yedek adresler asıl adresle **aynı sorgu/sorgu parametrelerini** korur:
    /// sağlayıcı kimliği sorguda taşıyan panellerde bunlar düşerse yedek adres
    /// yetkisiz olur ve teşhis yanlış çıkar.
    @MainActor
    func testFallbackKeepsQueryItems() {
        let url = "http://cdn.example.com/movie/user/pass/456.mkv?token=abc123"
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item(url, kind: .movie), isLive: false
        )
        guard candidates.count == 2 else {
            return XCTFail("iki aday bekleniyordu, gelen: \(candidates)")
        }
        XCTAssertEqual(candidates[1].query, "token=abc123")
    }

    /// Dizi bölümleri de VOD gibi ele alınır; tür ayrımı adres üretimini
    /// değiştirmemelidir.
    @MainActor
    func testSeriesEpisodeUsesVODRules() {
        let candidates = VLCPlayerEngine.playbackCandidates(
            for: item("\(vodBase).mkv", kind: .series), isLive: false
        )
        XCTAssertEqual(candidates.map(\.pathExtension), ["mkv", "mp4"])
    }
}
