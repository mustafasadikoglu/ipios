import Foundation
import SwiftUI

/// Canlı TV sekmesi: kanal listesi + yayın akışı (EPG).
///
/// EPG, kanal listesinden ayrı yüklenir: liste saniyeler içinde gelirken
/// program akışı daha yavaştır ve gelmediğinde kanalların gösterilmesini
/// engellememelidir.
@MainActor
final class LiveViewModel: CatalogViewModel {

    /// Kanal kimliğine göre programlar. Anahtar `epgChannelID ?? channel.id`.
    @Published private(set) var epgByChannel: [String: [EPGProgram]] = [:]
    @Published private(set) var isLoadingEPG = false

    private var epgTask: Task<Void, Never>?

    override func didLoad() async {
        await loadEPG()
    }

    // MARK: - EPG

    func loadEPG() async {
        guard let source = environment.sources.activeSource else { return }
        let epg = environment.sources.epgProvider(for: source)

        // XMLTV dosyaları onlarca megabayt olabilir; bu yüzden yalnızca
        // listeye gerçekten giren ilk kanallar için akış çekilir.
        let channelIDs: [String] = allItems.prefix(Self.epgChannelLimit).compactMap { item in
            guard case .channel(let channel) = item else { return nil }
            return channel.epgChannelID ?? channel.id
        }
        guard !channelIDs.isEmpty else { return }

        epgTask?.cancel()
        isLoadingEPG = true

        epgTask = Task { [weak self] in
            do {
                let programs = try await epg.programs(for: channelIDs, horizon: 12 * 3600)
                guard !Task.isCancelled else { return }
                self?.epgByChannel = programs
                self?.isLoadingEPG = false
            } catch is CancellationError {
                self?.isLoadingEPG = false
            } catch {
                // EPG ikincil bir bilgidir: alınamazsa liste çalışmaya devam
                // eder ve kullanıcıya hata gösterilmez.
                Log.epg.debug("EPG yuklenemedi: \(error.localizedDescription, privacy: .public)")
                self?.isLoadingEPG = false
            }
        }
        await epgTask?.value
    }

    /// Bir kanalın şu an oynayan ve sıradaki programı.
    func nowAndNext(for channel: Channel) -> (now: EPGProgram?, next: EPGProgram?) {
        programs(for: channel).reduce(into: (now: nil, next: nil)) { result, program in
            if program.isLive { result.now = program }
            else if program.start > Date(), result.next == nil { result.next = program }
        }
    }

    func programs(for channel: Channel) -> [EPGProgram] {
        let key = channel.epgChannelID ?? channel.id
        return (epgByChannel[key] ?? []).sorted { $0.start < $1.start }
    }

    private static let epgChannelLimit = 40
}
