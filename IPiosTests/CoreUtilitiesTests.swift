import XCTest
@testable import IPiOS

/// `Flexible*` sarmalayıcıları ve `AppError` eşlemesi.
///
/// Xtream panelleri aynı alanı bazen sayı, bazen string döndürür. Bu testler
/// toleransın korunmasını sağlar; kaybı tüm kanal listesinin boş gelmesine
/// yol açardı.
final class CoreUtilitiesTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - FlexibleInt

    func testFlexibleIntFromNumber() throws {
        XCTAssertEqual(try decode(FlexibleInt.self, "42").value, 42)
    }

    func testFlexibleIntFromString() throws {
        XCTAssertEqual(try decode(FlexibleInt.self, "\"42\"").value, 42)
    }

    func testFlexibleIntFromDouble() throws {
        XCTAssertEqual(try decode(FlexibleInt.self, "42.9").value, 42)
    }

    func testFlexibleIntFromNull() throws {
        XCTAssertNil(try decode(FlexibleInt.self, "null").value)
    }

    func testFlexibleIntFromGarbageIsNil() throws {
        XCTAssertNil(try decode(FlexibleInt.self, "\"abc\"").value)
    }

    // MARK: - FlexibleString

    func testFlexibleStringFromNumber() throws {
        XCTAssertEqual(try decode(FlexibleString.self, "101").value, "101")
    }

    func testFlexibleStringFromBool() throws {
        XCTAssertEqual(try decode(FlexibleString.self, "true").value, "true")
    }

    /// Xtream panelleri `cast`, `director` ve `genre` alanlarını sık sık dizi
    /// olarak döndürür. Bu alanlar `String?` iken tek bir yanıt tüm film/dizi
    /// listesinin çözümlenmesini düşürüyordu; öğeler birleştirilerek okunur.
    func testFlexibleStringFromArrayJoinsElements() throws {
        XCTAssertEqual(
            try decode(FlexibleString.self, #"["Ali Veli", "Ayşe Kaya"]"#).value,
            "Ali Veli, Ayşe Kaya"
        )
    }

    /// Boş dizi `nil` olur; ekranda boş bir tür etiketi çizilmez.
    func testFlexibleStringFromEmptyArrayIsNil() throws {
        XCTAssertNil(try decode(FlexibleString.self, "[]").value)
    }

    /// Dizi öğeleri dize olmayabilir (bazı paneller sayı gönderir).
    func testFlexibleStringFromMixedArray() throws {
        XCTAssertEqual(try decode(FlexibleString.self, "[1975, \"Dram\"]").value, "1975, Dram")
    }

    /// Dizi içindeki boş dizeler atlanır; sonuç "A, , B" olmamalı.
    func testFlexibleStringFromArraySkipsEmptyElements() throws {
        XCTAssertEqual(try decode(FlexibleString.self, #"["A", "", "B"]"#).value, "A, B")
    }

    /// İç içe dizi gibi çözülemeyen bir değer çökme yerine `nil` verir.
    func testFlexibleStringFromUnsupportedValueIsNil() throws {
        XCTAssertNil(try decode(FlexibleString.self, #"{"a": 1}"#).value)
    }

    /// VOD yanıtı, alanları dizi olarak döndüren bir panelle de çözülebilmeli.
    ///
    /// Bu, film/dizi listelerinin boş gelmesine yol açan asıl kusurun
    /// regresyon testidir: `get_vod_streams` gövdesinin tamamı tek bir alan
    /// yüzünden düşüyordu.
    func testVODResponseDecodesWhenCastIsAnArray() throws {
        let json = """
        [{
            "num": 1,
            "name": "Örnek Film",
            "stream_id": 9,
            "container_extension": "mp4",
            "cast": ["Ali Veli", "Ayşe Kaya"],
            "director": ["Yönetmen"],
            "genre": ["Dram", "Gerilim"],
            "releaseDate": "1975-01-01"
        }]
        """
        let list = try decode([XtreamDTO.VODStreamDTO].self, json)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].cast?.value, "Ali Veli, Ayşe Kaya")
        XCTAssertEqual(list[0].genre?.value, "Dram, Gerilim")
    }

    /// Aynı tolerans dizi listesi (`get_series`) için de geçerli.
    func testSeriesResponseDecodesWhenCastIsAnArray() throws {
        let json = """
        [{
            "series_id": 5,
            "name": "Örnek Dizi",
            "cast": ["Oyuncu"],
            "genre": ["Komedi"]
        }]
        """
        let list = try decode([XtreamDTO.SeriesDTO].self, json)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].genre?.value, "Komedi")
    }

    // MARK: - FlexibleDouble

    /// Bazı Avrupa panelleri ondalık ayırıcı olarak virgül gönderir.
    func testFlexibleDoubleAcceptsCommaDecimalSeparator() throws {
        XCTAssertEqual(try decode(FlexibleDouble.self, "\"7,5\"").value, 7.5)
    }

    // MARK: - AppError

    func testUnauthorizedAndBadCredentialsShareMessage() {
        XCTAssertEqual(AppError.unauthorized.errorDescription,
                       AppError.badCredentials.errorDescription)
    }

    func testErrorMessagesAreLocalizedNotKeys() {
        // Anahtar çözülemezse `L.t` anahtarın kendisini döner; bu da ekranda
        // "error.timeout" gibi bir metin görünmesi demektir.
        XCTAssertNotEqual(AppError.timeout.errorDescription, "error.timeout")
        XCTAssertNotEqual(AppError.unknown.errorDescription, "error.unknown")
    }

    func testServerErrorIncludesStatusCode() {
        let message = AppError.server(status: 503).errorDescription ?? ""
        XCTAssertTrue(message.contains("503"), "Durum kodu mesaja gömülmeli: \(message)")
    }

    func testRetryableClassification() {
        XCTAssertTrue(AppError.timeout.isRetryable)
        XCTAssertTrue(AppError.network(underlying: "x").isRetryable)
        XCTAssertTrue(AppError.server(status: 500).isRetryable)
        XCTAssertTrue(AppError.sourceUnreachable.isRetryable)

        XCTAssertFalse(AppError.unauthorized.isRetryable)
        XCTAssertFalse(AppError.notFound.isRetryable)
        XCTAssertFalse(AppError.cancelled.isRetryable)
        XCTAssertFalse(AppError.playlistEmpty.isRetryable)
    }

    // MARK: - HTTPError

    func testHTTPErrorMapping() {
        XCTAssertEqual(HTTPError(statusCode: 401, url: nil).appError, .unauthorized)
        XCTAssertEqual(HTTPError(statusCode: 403, url: nil).appError, .unauthorized)
        XCTAssertEqual(HTTPError(statusCode: 404, url: nil).appError, .notFound)
        XCTAssertEqual(HTTPError(statusCode: 502, url: nil).appError, .server(status: 502))
    }

    func testHTTPErrorCategoryFlags() {
        XCTAssertTrue(HTTPError(statusCode: 404, url: nil).isClientError)
        XCTAssertTrue(HTTPError(statusCode: 500, url: nil).isServerError)
        XCTAssertFalse(HTTPError(statusCode: 200, url: nil).isClientError)
    }
}
