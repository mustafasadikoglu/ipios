import XCTest
@testable import IPiOS

/// M3U ayrıştırıcısının hoşgörülü davranışını doğrular.
///
/// Bu testler ağa çıkmaz; yalnızca saf metin ayrıştırma mantığını sınar.
/// Gerçek sağlayıcı listeleri çok düzensiz olduğu için (eksik tırnak, bozuk
/// satır sonu, BOM) buradaki senaryolar doğrudan sahadan alınmıştır.
final class M3UParserTests: XCTestCase {

    // MARK: - Temel ayrıştırma

    func testParsesSingleEntryWithAllAttributes() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="trt1.tr" tvg-name="TRT 1" tvg-logo="http://x/trt1.png" group-title="Ulusal",TRT 1
        http://server/live/user/pass/101.m3u8
        """

        let result = M3UParser.parse(text)

        XCTAssertEqual(result.entries.count, 1)
        guard let entry = result.entries.first else { return }
        XCTAssertEqual(entry.title, "TRT 1")
        XCTAssertEqual(entry.tvgID, "trt1.tr")
        XCTAssertEqual(entry.tvgName, "TRT 1")
        XCTAssertEqual(entry.groupTitle, "Ulusal")
        XCTAssertEqual(entry.logoURL?.absoluteString, "http://x/trt1.png")
        XCTAssertEqual(entry.durationRaw, "-1")
        XCTAssertEqual(entry.url.absoluteString, "http://server/live/user/pass/101.m3u8")
        XCTAssertEqual(result.groupNames, ["Ulusal"])
    }

    /// Süre öbeği (`-1`) attribute ayrıştırmasına karışmamalıdır.
    ///
    /// Bu, ayrıştırıcıda bir zamanlar gerçek bir hataya yol açmıştı: `-1` gövdeden
    /// çıkarılmadığında anahtar `-1 tvg-id` oluyor, boşluk içerdiği için
    /// reddediliyor ve tarama her `=` işaretini atlayıp **tüm** attribute'ları
    /// kaybediyordu. Aşağıdaki iddialar o hatanın geri gelmemesini sağlar.
    func testDurationTokenDoesNotShadowAttributes() {
        let text = """
        #EXTINF:-1 tvg-id="a.tr" group-title="Haber",Kanal A
        http://s/a.m3u8
        """

        let entry = M3UParser.parse(text).entries.first
        XCTAssertNotNil(entry?.tvgID, "Süre öbeği attribute taramasını bozmamalı")
        XCTAssertEqual(entry?.tvgID, "a.tr")
        XCTAssertEqual(entry?.groupTitle, "Haber")
    }

    func testZeroDurationIsCaptured() {
        let entry = M3UParser.parse("#EXTINF:0 group-title=\"X\",Ad\nhttp://s/a.m3u8").entries.first
        XCTAssertEqual(entry?.durationRaw, "0")
        XCTAssertEqual(entry?.groupTitle, "X")
    }

    func testExtinfWithoutDurationStillParsesAttributes() {
        let entry = M3UParser.parse("#EXTINF: tvg-id=\"b\",Kanal B\nhttp://s/b.m3u8").entries.first
        XCTAssertEqual(entry?.tvgID, "b")
        XCTAssertEqual(entry?.title, "Kanal B")
        XCTAssertNil(entry?.durationRaw)
    }

    // MARK: - Başlık kuralları

    /// Başlık virgül içerebilir; sınır **ilk** virgüldür.
    func testTitleMayContainCommas() {
        let entry = M3UParser.parse("#EXTINF:-1 group-title=\"X\",Haber, Spor\nhttp://s/a.m3u8").entries.first
        XCTAssertEqual(entry?.title, "Haber, Spor")
    }

    /// Bazı listeler başlığı boş bırakıp `tvg-name` kullanır.
    func testFallsBackToTvgNameWhenTitleEmpty() {
        let entry = M3UParser.parse("#EXTINF:-1 tvg-name=\"Yedek Ad\",\nhttp://s/a.m3u8").entries.first
        XCTAssertEqual(entry?.title, "Yedek Ad")
        XCTAssertEqual(entry?.effectiveTitle, "Yedek Ad")
    }

    func testEffectiveTitleFallsBackToLastPathComponent() {
        let entry = M3UParser.parse("http://server/path/stream.ts").entries.first
        XCTAssertEqual(entry?.title, "")
        XCTAssertEqual(entry?.effectiveTitle, "stream.ts")
    }

    // MARK: - Gruplar

    func testExtGroupUsedWhenGroupTitleMissing() {
        let text = """
        #EXTINF:-1,Kanal
        #EXTGRP:Spor
        http://s/a.m3u8
        """
        let entry = M3UParser.parse(text).entries.first
        XCTAssertEqual(entry?.groupTitle, nil)
        XCTAssertEqual(entry?.extGroup, "Spor")
        XCTAssertEqual(entry?.effectiveGroup, "Spor")
    }

    func testGroupNamesAreUniqueAndOrderedByFirstAppearance() {
        let text = """
        #EXTINF:-1 group-title="B",1
        http://s/1.m3u8
        #EXTINF:-1 group-title="A",2
        http://s/2.m3u8
        #EXTINF:-1 group-title="B",3
        http://s/3.m3u8
        """
        XCTAssertEqual(M3UParser.parse(text).groupNames, ["B", "A"])
    }

    // MARK: - Dayanıklılık

    func testNormalizesCRLFAndBOM() {
        let text = "\u{FEFF}#EXTM3U\r\n#EXTINF:-1 group-title=\"X\",A\r\nhttp://s/a.m3u8\r\n"
        let result = M3UParser.parse(text)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.groupTitle, "X")
    }

    func testSkipsUnparseableURLLinesWithoutAborting() {
        let text = """
        #EXTINF:-1 group-title="X",Bozuk
        bu-bir-url-degil
        #EXTINF:-1 group-title="X",Saglam
        http://s/good.m3u8
        """
        let result = M3UParser.parse(text)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.title, "Saglam")
    }

    func testIgnoresUnknownDirectives() {
        let text = """
        #EXTM3U
        #KODIPROP:inputstream.adaptive.license_type=clearkey
        #EXTVLCOPT:network-caching=1000
        #EXTINF:-1,Kanal
        http://s/a.m3u8
        """
        XCTAssertEqual(M3UParser.parse(text).entries.count, 1)
    }

    func testHandlesUnquotedAttributeValues() {
        let entry = M3UParser.parse("#EXTINF:-1 tvg-id=abc group-title=Haber,Kanal\nhttp://s/a.m3u8").entries.first
        XCTAssertEqual(entry?.tvgID, "abc")
        XCTAssertEqual(entry?.groupTitle, "Haber")
    }

    /// Kapanış tırnağı olmayan bozuk satır satır sonuna kadar okunmalı, çökmemeli.
    func testUnterminatedQuotedValueDoesNotCrash() {
        let entry = M3UParser.parse("#EXTINF:-1 tvg-id=\"abc,Kanal\nhttp://s/a.m3u8").entries.first
        XCTAssertEqual(entry?.tvgID, "abc,Kanal")
    }

    func testEmptyInputProducesEmptyResult() {
        let result = M3UParser.parse("")
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.groupNames.isEmpty)
    }

    /// Aynı akış birden fazla listelenirse indeksler kaynak sırasını izlemelidir.
    func testIndicesFollowSourceOrder() {
        let text = """
        #EXTINF:-1,A
        http://s/a.m3u8
        #EXTINF:-1,B
        http://s/b.m3u8
        #EXTINF:-1,C
        http://s/c.m3u8
        """
        XCTAssertEqual(M3UParser.parse(text).entries.map(\.index), [0, 1, 2])
    }

    func testLogoAttributeAcceptsLegacyLogoKey() {
        let entry = M3UParser.parse("#EXTINF:-1 logo=\"http://x/l.png\",A\nhttp://s/a.m3u8").entries.first
        XCTAssertEqual(entry?.logoURL?.absoluteString, "http://x/l.png")
    }

    func testAttributeKeysAreLowercased() {
        let entry = M3UParser.parse("#EXTINF:-1 TVG-ID=\"upper\",A\nhttp://s/a.m3u8").entries.first
        XCTAssertEqual(entry?.tvgID, "upper")
    }
}
