import XCTest
@testable import IPiOS

/// XMLTV zaman damgası ayrıştırmasını doğrular.
///
/// XMLTV, sağlayıcıdan sağlayıcıya değişen üç farklı damga biçimi kullanır.
/// Yanlış ayrıştırma, yayın akışında programların yanlış saatte görünmesine
/// yol açar; bu yüzden saat dilimi kaydırması ayrıca sınanır.
final class XMLTVDateTests: XCTestCase {

    /// Karşılaştırmaları okunur kılmak için sabit bir biçimlendirici.
    private func utc(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    func testParsesFullTimestampWithPositiveOffset() {
        let date = XMLTVParser.parseXMLTVDate("20260921200000 +0300")
        XCTAssertNotNil(date)
        // 20:00 +03:00 == 17:00 UTC
        XCTAssertEqual(utc(date!), "2026-09-21 17:00:00")
    }

    func testParsesFullTimestampWithNegativeOffset() {
        let date = XMLTVParser.parseXMLTVDate("20260921200000 -0500")
        XCTAssertEqual(utc(date!), "2026-09-22 01:00:00")
    }

    /// Saat dilimi verilmezse UTC kabul edilir.
    func testParsesTimestampWithoutOffsetAsUTC() {
        let date = XMLTVParser.parseXMLTVDate("20260921200000")
        XCTAssertEqual(utc(date!), "2026-09-21 20:00:00")
    }

    /// Saniyesiz (12 haneli) damga da geçerlidir.
    func testParsesTimestampWithoutSeconds() {
        let date = XMLTVParser.parseXMLTVDate("202609212000 +0300")
        XCTAssertEqual(utc(date!), "2026-09-21 17:00:00")
    }

    func testParsesDateOnly() {
        let date = XMLTVParser.parseXMLTVDate("20260921")
        XCTAssertEqual(utc(date!), "2026-09-21 00:00:00")
    }

    func testTrimsSurroundingWhitespace() {
        let date = XMLTVParser.parseXMLTVDate("  20260921200000 +0300  ")
        XCTAssertEqual(utc(date!), "2026-09-21 17:00:00")
    }

    func testRejectsTooShortInput() {
        XCTAssertNil(XMLTVParser.parseXMLTVDate("2026"))
        XCTAssertNil(XMLTVParser.parseXMLTVDate(""))
    }

    func testRejectsGarbage() {
        XCTAssertNil(XMLTVParser.parseXMLTVDate("selam-dunya"))
    }

    /// Yarım saatlik saat dilimleri (Hindistan +0530) doğru kaydırılmalı.
    func testHandlesHalfHourTimeZone() {
        let date = XMLTVParser.parseXMLTVDate("20260921200000 +0530")
        XCTAssertEqual(utc(date!), "2026-09-21 14:30:00")
    }
}
