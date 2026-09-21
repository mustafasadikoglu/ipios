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
