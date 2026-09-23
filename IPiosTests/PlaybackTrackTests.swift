import XCTest
@testable import IPiOS

/// Ses/altyazı izi seçiminin model kurallarını doğrular.
///
/// **Neden gerekli:** seçim mantığı üç katmana dağılmıştır (model + motor +
/// görünüm) ve üçü de sessizce yanlış davranabilir. En kritik kural şudur:
/// libvlc iz nesneleri **her okumada yeniden üretilir** (`VLCMediaPlayer
/// (Tracks)` kategorisi, sürüm `4.0.0-a24`); bu yüzden seçim nesne kimliğiyle
/// değil **`trackId` ile** yapılmalıdır. Bu kural bozulursa kullanıcı menüyü
/// her açtığında farklı bir iz seçili görünür ve seçim "kayar".
///
/// Mantığın derleyicisiz sınanan portu `scripts/iz_mantik_testi.py` içindedir;
/// buradaki testler aynı kuralları **gerçek Swift tipleriyle** doğrular.
final class PlaybackTrackTests: XCTestCase {

    // MARK: - Yardımcılar

    private func track(
        _ id: String,
        name: String = "",
        language: String? = nil,
        kind: PlaybackTrack.Kind = .audio,
        ordinal: Int = 0
    ) -> PlaybackTrack {
        PlaybackTrack(id: id, name: name, language: language, kind: kind, ordinal: ordinal)
    }

    // MARK: - Menü görünürlüğü

    /// Tek ses izli ve altyazısız içerikte menü **sunulmaz**: kullanıcıya
    /// hiçbir seçenek gösterilmezdi.
    func testSingleAudioWithoutSubtitlesHasNoChoice() {
        let set = PlaybackTrackSet(audio: [track("1")], subtitles: [])
        XCTAssertFalse(set.hasAudioChoice)
        XCTAssertFalse(set.hasSubtitleChoice)
        XCTAssertFalse(set.hasAnyChoice)
    }

    /// İki ses izi seçim sunar.
    func testMultipleAudioTracksOfferChoice() {
        let set = PlaybackTrackSet(audio: [track("1"), track("2")], subtitles: [])
        XCTAssertTrue(set.hasAudioChoice)
        XCTAssertTrue(set.hasAnyChoice)
    }

    /// **Tek ses izi olsa bile** altyazı varsa menü sunulur; altyazı seçimi
    /// tek başına yeterlidir.
    func testSubtitlesAloneJustifyTheMenu() {
        let set = PlaybackTrackSet(
            audio: [track("1")],
            subtitles: [track("10", kind: .subtitle)]
        )
        XCTAssertFalse(set.hasAudioChoice)
        XCTAssertTrue(set.hasSubtitleChoice)
        XCTAssertTrue(set.hasAnyChoice)
    }

    /// Altyazı bölümü yalnızca gerçekten altyazı varken gösterilir.
    func testSubtitleSectionHiddenWhenNoSubtitles() {
        let set = PlaybackTrackSet(audio: [track("1"), track("2")])
        XCTAssertFalse(set.hasSubtitleChoice)
    }

    // MARK: - Kimlikle eşleşme

    /// Seçim **kimlikle** bulunur, sırayla değil. Nesneler her okumada yeniden
    /// üretildiği için liste karşılaştırması nesne kimliğine dayanamaz.
    func testIndexLookupUsesIdentifier() {
        let set = PlaybackTrackSet(audio: [track("a"), track("b"), track("c")])
        XCTAssertEqual(set.index(of: "c", in: .audio), 2)
        XCTAssertEqual(set.index(of: "a", in: .audio), 0)
    }

    /// Bilinmeyen kimlik `nil` döner; çağıran taraf seçim yapmaz.
    func testUnknownIdentifierReturnsNil() {
        let set = PlaybackTrackSet(audio: [track("a")])
        XCTAssertNil(set.index(of: "yok", in: .audio))
    }

    /// Aynı kimlik listeler arasında karışmaz: ses kimliği altyazı listesinde
    /// aranırsa bulunmamalıdır.
    func testKindsDoNotLeakIntoLists() {
        let set = PlaybackTrackSet(
            audio: [track("a")],
            subtitles: [track("b", kind: .subtitle)]
        )
        XCTAssertEqual(set.index(of: "b", in: .subtitle), 0)
        XCTAssertNil(set.index(of: "b", in: .audio))
    }

    // MARK: - Seçili iz

    /// Seçili ses izi kimlikten bulunur.
    func testSelectedAudioResolvedByIdentifier() {
        let set = PlaybackTrackSet(
            audio: [track("1"), track("2")],
            selectedAudioID: "2"
        )
        XCTAssertEqual(set.selectedAudio?.id, "2")
    }

    /// **Altyazı kapalı olmak geçerli bir durumdur.** `nil` seçim "hata" değil,
    /// "Kapalı" satırına karşılık gelir.
    func testNoSelectedSubtitleMeansSubtitlesOff() {
        let set = PlaybackTrackSet(
            audio: [track("1")],
            subtitles: [track("10", kind: .subtitle)],
            selectedSubtitleID: nil
        )
        XCTAssertNil(set.selectedSubtitle)
        XCTAssertTrue(set.hasSubtitleChoice, "'Kapalı' satırı hâlâ sunulmalı")
    }

    /// Kimlik listede yoksa (iz kaldırılmışsa) seçili iz `nil` döner ve
    /// çökmez.
    func testStaleSelectionIdentifierIsTolerated() {
        let set = PlaybackTrackSet(audio: [track("1")], selectedAudioID: "99")
        XCTAssertNil(set.selectedAudio)
    }

    // MARK: - Etiket kuralları

    /// Gömülü izlerin adı çoğu zaman boştur; etiket sıra numarasıyla üretilir
    /// ve numara **1 tabanlı** olmalıdır (0 tabanlı `ordinal` ekranda "Ses 0"
    /// gibi görünürdü).
    func testEmptyNameIsDetectedAndOrdinalIsOneBased() {
        let first = track("1", name: "", ordinal: 0)
        let second = track("2", name: "", ordinal: 1)

        XCTAssertTrue(first.hasEmptyName)
        XCTAssertEqual(first.displayOrdinal, 1)
        XCTAssertEqual(second.displayOrdinal, 2)
    }

    /// Yalnızca boşluktan oluşan ad da **boş** sayılır; aksi hâlde menüde boş
    /// bir satır belirir ve kullanıcı hangi izi seçtiğini bilemez.
    func testWhitespaceOnlyNameCountsAsEmpty() {
        let padded = track("1", name: "   ")
        XCTAssertTrue(padded.hasEmptyName)
    }

    /// Gerçek adı olan iz numaralandırılmaz.
    func testNamedTrackKeepsItsName() {
        let named = track("1", name: "Türkçe AC3", language: "tur")
        XCTAssertFalse(named.hasEmptyName)
        XCTAssertEqual(named.name, "Türkçe AC3")
        XCTAssertEqual(named.language, "tur")
    }

    // MARK: - Boş küme

    /// Durdurulduğunda iz listesi boşalır; önceki filmin seçenekleri bir
    /// sonraki içerik açılana kadar menüde kalmamalıdır.
    func testEmptySetOffersNothing() {
        XCTAssertFalse(PlaybackTrackSet.empty.hasAnyChoice)
        XCTAssertNil(PlaybackTrackSet.empty.index(of: "1", in: .audio))
        XCTAssertNil(PlaybackTrackSet.empty.selectedAudio)
        XCTAssertNil(PlaybackTrackSet.empty.selectedSubtitle)
    }
}
