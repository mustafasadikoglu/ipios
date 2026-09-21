import Foundation

/// `NetworkClient` dışında (örneğin AVPlayer hata mesajlarında) kullanılan
/// ham HTTP durum kodu sarmalayıcısı.
struct HTTPError: Error, Equatable {
    let statusCode: Int
    let url: URL?

    var isClientError: Bool { (400...499).contains(statusCode) }
    var isServerError: Bool { (500...599).contains(statusCode) }

    var appError: AppError {
        switch statusCode {
        case 401, 403: return .unauthorized
        case 404: return .notFound
        default: return isServerError ? .server(status: statusCode) : .unknown
        }
    }
}
