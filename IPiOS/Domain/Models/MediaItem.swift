import Foundation

/// Oynatılabilir her şeyin uyduğu ortak arayüz.
///
/// Favoriler, arama ve "son izlenenler" bu protokol sayesinde kanal, film ve
/// bölüm ayrımı yapmadan tek koleksiyonda çalışır.
protocol MediaItem: Identifiable, Hashable {
    var id: String { get }
    var title: String { get }
    var imageURL: URL? { get }
    /// Oynatıcıya verilecek akış adresi.
    var streamURL: URL { get }
    /// Kaynağın kimliği; favorilerin doğru kaynağa bağlanması için.
    var sourceID: UUID { get }
    /// İçerik türü.
    var kind: CategoryKind { get }
}

extension MediaItem {
    var stableKey: String {
        "\(sourceID.uuidString)::\(kind.rawValue)::\(id)"
    }
}

/// Favoriler ve son izlenenler listesinde saklanan hafif kayıt.
///
/// `MediaItem`'ın kendisi yerine bu yapı saklanır çünkü liste yeniden
/// yüklendiğinde öğe artık mevcut olmayabilir; kayıt yine de anlamlı kalır.
struct MediaReference: Identifiable, Hashable, Codable {
    let id: String
    let sourceID: UUID
    let kind: CategoryKind
    let title: String
    let imageURLString: String?
    /// Favorilere eklendiği / izlendiği zaman.
    var timestamp: Date

    init(
        id: String,
        sourceID: UUID,
        kind: CategoryKind,
        title: String,
        imageURLString: String?,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.kind = kind
        self.title = title
        self.imageURLString = imageURLString
        self.timestamp = timestamp
    }

    init(item: any MediaItem, timestamp: Date = Date()) {
        self.init(
            id: item.id,
            sourceID: item.sourceID,
            kind: item.kind,
            title: item.title,
            imageURLString: item.imageURL?.absoluteString,
            timestamp: timestamp
        )
    }

    /// Oynatılamayan üst düzey kayıtlar için (ör. dizi).
    ///
    /// `Series` bilerek `MediaItem`'a uymaz: oynatılabilen şey bölümlerdir.
    /// Buna karşın dizinin kendisi favorilere eklenebildiği için kaydı
    /// üretilebilmelidir.
    init(series: Series, timestamp: Date = Date()) {
        self.init(
            id: series.id,
            sourceID: series.sourceID,
            kind: .series,
            title: series.title,
            imageURLString: series.imageURL?.absoluteString,
            timestamp: timestamp
        )
    }

    var imageURL: URL? {
        imageURLString.flatMap(URL.init(string:))
    }

    var stableKey: String {
        "\(sourceID.uuidString)::\(kind.rawValue)::\(id)"
    }
}
