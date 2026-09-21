import Foundation

/// `URLSession` üzerine async/await sarmalayıcı.
///
/// Sorumluluklar: yeniden deneme, zaman aşımı, HTTP durum kodu haritalaması,
/// JSON çözümleme ve ham veri indirme.
actor NetworkClient {

    struct Configuration {
        var requestTimeout: TimeInterval = 15
        var downloadTimeout: TimeInterval = 30
        var maxRetries: Int = 3
        var baseRetryDelay: Duration = .milliseconds(400)
        /// Yeniden denemeye değer HTTP durum kodları.
        var retryableStatusCodes: Set<Int> = [408, 425, 429, 500, 502, 503, 504]
    }

    private let configuration: Configuration
    private let session: URLSession
    private let decoder: JSONDecoder

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfig.timeoutIntervalForResource = configuration.downloadTimeout
        sessionConfig.waitsForConnectivity = true
        sessionConfig.requestCachePolicy = .useProtocolCachePolicy
        sessionConfig.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024
        )
        self.session = URLSession(configuration: sessionConfig)
        self.decoder = JSONDecoder()
    }

    // MARK: - Public API

    /// JSON yanıtı çekip `T` tipine çözer.
    func getJSON<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        headers: [String: String] = [:]
    ) async throws -> T {
        let data = try await getData(from: url, headers: headers)
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            Log.network.error("JSON cozumleme hatasi: \(String(describing: error), privacy: .public)")
            throw AppError.decoding(context: Self.describe(error))
        }
    }

    /// Ham `Data` çeker.
    func getData(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        let (data, response) = try await execute(url: url, headers: headers)
        _ = response
        return data
    }

    /// Metin yanıtı çeker (M3U playlist ve XMLTV için).
    func getString(from url: URL, headers: [String: String] = [:]) async throws -> String {
        let data = try await getData(from: url, headers: headers)
        // Playlist ve EPG dosyaları çoğunlukla UTF-8; bozuk durumda Latin-9'a düşülür.
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin = String(data: data, encoding: .isoLatin1) {
            return latin
        }
        throw AppError.decoding(context: L.t("error.decoding.encoding"))
    }

    /// Büyük dosyaları diske indirir, ilerlemeyi bildirir.
    /// XMLTV gibi yüz megabaytı aşabilen dosyalar için kullanılır.
    func download(
        from url: URL,
        to destination: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        var attempt = 0
        while true {
            do {
                let (temporaryURL, response) = try await session.download(from: url)
                try validate(response)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                onProgress?(1.0)
                return destination
            } catch {
                let mapped = Self.map(error)
                guard mapped.isRetryable, attempt < configuration.maxRetries else {
                    throw mapped
                }
                attempt += 1
                try await backoff(attempt: attempt)
            }
        }
    }

    // MARK: - Private

    private func execute(
        url: URL,
        headers: [String: String]
    ) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("IPiOS/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                Log.network.debug("GET \(Log.redacted(url), privacy: .public)")

                let (data, response) = try await session.data(for: request)
                try validate(response)
                return (data, response)
            } catch {
                let mapped = Self.map(error)
                guard mapped.isRetryable, attempt < configuration.maxRetries else {
                    throw mapped
                }
                attempt += 1
                Log.network.warning("Yeniden deneniyor (\(attempt)/\(self.configuration.maxRetries))")
                try await backoff(attempt: attempt)
            }
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw AppError.unauthorized
        case 404:
            throw AppError.notFound
        default:
            throw AppError.server(status: http.statusCode)
        }
    }

    private func backoff(attempt: Int) async throws {
        let multiplier = Int(pow(2.0, Double(attempt - 1)))
        let delay = configuration.baseRetryDelay * multiplier
        let capped = min(delay, .seconds(8))
        try await Task.sleep(for: capped)
    }

    private static func map(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case (NSURLErrorDomain, NSURLErrorTimedOut):
            return .timeout
        case (NSURLErrorDomain, NSURLErrorCancelled):
            return .cancelled
        case (NSURLErrorDomain, NSURLErrorCannotFindHost),
             (NSURLErrorDomain, NSURLErrorCannotConnectToHost),
             (NSURLErrorDomain, NSURLErrorNetworkConnectionLost),
             (NSURLErrorDomain, NSURLErrorNotConnectedToInternet):
            return .sourceUnreachable
        default:
            return .network(underlying: nsError.localizedDescription)
        }
    }

    /// Çözümleme hatasını kullanıcıya gösterilebilecek bir metne çevirir.
    ///
    /// - Note: Dönen metin `AppError.decoding(context:)` üzerinden doğrudan
    ///   ekrana çıkar; bu yüzden sabit metin değil, yerelleştirilmiş metin
    ///   kullanılır. Teknik ayrıntı (CodingKey, tip adı, codingPath) log'a
    ///   yazılır — kullanıcıya ham `CodingKey` göstermenin bir faydası yok.
    private static func describe(_ error: DecodingError) -> String {
        Log.network.debug("Cozumleme ayrintisi: \(String(describing: error), privacy: .public)")
        switch error {
        case .keyNotFound:
            return L.t("error.decoding.field")
        case .typeMismatch:
            return L.t("error.decoding.type")
        case .valueNotFound:
            return L.t("error.decoding.empty")
        case .dataCorrupted:
            return L.t("error.decoding.corrupt")
        @unknown default:
            return L.t("error.decoding.unknown")
        }
    }
}
