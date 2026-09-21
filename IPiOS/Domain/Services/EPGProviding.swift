import Foundation

/// EPG (yayın akışı) sağlayıcı arayüzü.
protocol EPGProviding: Sendable {

    /// Verilen kanal kimlikleri için `[0, horizon]` aralığındaki programları döner.
    /// - Parameters:
    ///   - channelIDs: EPG kanal kimlikleri (`tvg-id`).
    ///   - horizon: Şu andan itibaren kaç saat ilerisi getirilsin.
    func programs(for channelIDs: [String], horizon: TimeInterval) async throws -> [String: [EPGProgram]]

    /// Tek bir kanal için şu an ve sonrasındaki birkaç program.
    func nowAndNext(channelID: String) async throws -> (now: EPGProgram?, next: EPGProgram?)

    /// Önbelleği temizler.
    func invalidateCache() async
}

extension EPGProviding {
    /// Varsayılan ufuk: 24 saat.
    func programs(for channelIDs: [String]) async throws -> [String: [EPGProgram]] {
        try await programs(for: channelIDs, horizon: 24 * 3600)
    }
}

/// Basit, önbellek tutmayan / hiç EPG sağlamayan kaynaklar için boş implementasyon.
struct EmptyEPGProvider: EPGProviding {
    func programs(for channelIDs: [String], horizon: TimeInterval) async throws -> [String: [EPGProgram]] {
        [:]
    }

    func nowAndNext(channelID: String) async throws -> (now: EPGProgram?, next: EPGProgram?) {
        (nil, nil)
    }

    func invalidateCache() async {}
}
