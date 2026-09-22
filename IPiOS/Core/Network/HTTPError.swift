import Foundation

/// `NetworkClient` dışında, tek bir HTTP yanıtının durum kodunu taşımak için
/// kullanılan ham sarmalayıcı.
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
