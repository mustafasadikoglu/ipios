import Foundation

/// Son izlenenler ve izleme konumlarını yönetir.
///
/// İki ayrı kayıt tutulur:
/// - `recents`: son izlenen öğelerin listesi (en yeni başta, en fazla 50 kayıt).
/// - `positions`: VOD/dizi için kaldığı yer (saniye) ve toplam süre.
///
/// Canlı kanallar için konum tutulmaz — yalnızca "son izlenenler" listesine girer.
@MainActor
final class RecentsRepository: ObservableObject {

    /// Devam edilecek içerik.
    struct Position: Codable, Hashable {
        let stableKey: String
        var seconds: Double
        var duration: Double?
        var updatedAt: Date

        /// İçerik baştan çok az izlendiyse veya bitmeye çok yakınsa devam önerilmez.
        var isResumable: Bool {
            guard seconds > 15 else { return false }
            if let duration, duration > 0 {
                return seconds < duration - 30
            }
            return true
        }

        var progress: Double {
            guard let duration, duration > 0 else { return 0 }
            return min(max(seconds / duration, 0), 1)
        }
    }

    @Published private(set) var recents: [MediaReference] = []
    @Published private(set) var positions: [String: Position] = [:]

    private let store: JSONFileStore
    private let recentsFile = "recents.json"
    private let positionsFile = "positions.json"
    private let maxRecents = 50

    init(store: JSONFileStore = JSONFileStore()) {
        self.store = store
    }

    func load() async {
        do {
            recents = try await store.load([MediaReference].self, from: recentsFile) ?? []
            let stored = try await store.load([String: Position].self, from: positionsFile) ?? [:]
            positions = stored
        } catch {
            Log.storage.error("Son izlenenler yuklenemedi: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Son izlenenler

    func record(_ item: MediaItem) async {
        let key = item.stableKey
        recents.removeAll { $0.stableKey == key }
        recents.insert(MediaReference(item: item), at: 0)
        if recents.count > maxRecents {
            recents = Array(recents.prefix(maxRecents))
        }
        await persistRecents()
    }

    func clearRecents() async {
        recents.removeAll()
        await persistRecents()
    }

    // MARK: - İzleme konumu

    func position(for item: MediaItem) -> Position? {
        let position = positions[item.stableKey]
        return position?.isResumable == true ? position : nil
    }

    func savePosition(for item: MediaItem, seconds: Double, duration: Double?) async {
        guard seconds.isFinite, seconds >= 0 else { return }
        positions[item.stableKey] = Position(
            stableKey: item.stableKey,
            seconds: seconds,
            duration: duration,
            updatedAt: Date()
        )
        await persistPositions()
    }

    func clearPosition(for item: MediaItem) async {
        positions.removeValue(forKey: item.stableKey)
        await persistPositions()
    }

    func clearAllPositions() async {
        positions.removeAll()
        await persistPositions()
    }

    /// Devam edilebilecek içerikler, en yeni önce.
    var resumeList: [(reference: MediaReference, position: Position)] {
        let byKey = Dictionary(uniqueKeysWithValues: recents.map { ($0.stableKey, $0) })
        return positions.values
            .filter(\.isResumable)
            .sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { position in
                guard let reference = byKey[position.stableKey] else { return nil }
                return (reference, position)
            }
    }

    // MARK: - Private

    private func persistRecents() async {
        try? await store.save(recents, as: recentsFile)
    }

    private func persistPositions() async {
        try? await store.save(positions, as: positionsFile)
    }
}
