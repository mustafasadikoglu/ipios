import Foundation

/// İçerik türü. Kategoriler bu türe göre gruplanır.
enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case live
    case movie
    case series

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .live: return L.t("kind.live")
        case .movie: return L.t("kind.movie")
        case .series: return L.t("kind.series")
        }
    }

    var iconName: String {
        switch self {
        case .live: return "tv"
        case .movie: return "film"
        case .series: return "rectangle.stack"
        }
    }
}

/// Bir içerik kategorisi (Xtream `get_*_categories` yanıtı veya M3U `group-title`).
struct Category: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let kind: CategoryKind

    /// Xtream kategori sıralaması.
    let order: Int

    /// Bu kategorideki öğe sayısı; bilinmiyorsa `nil`.
    var itemCount: Int?

    init(id: String, name: String, kind: CategoryKind, order: Int = 0, itemCount: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.order = order
        self.itemCount = itemCount
    }
}

extension Category {

    /// "Tümü" yapay kategorisinin kimliği.
    ///
    /// Sağlayıcıdan gelen bir kimlikle çakışmaması için başında ve sonunda
    /// alt çizgi kullanılır; Xtream kategori kimlikleri sayısaldır.
    static let allID = "__all__"

    /// Listenin başına konan "Tümü" kategorisi. Gerçek bir kategori değildir;
    /// yalnızca filtresiz görünümü temsil eder.
    static func all(kind: CategoryKind) -> Category {
        Category(id: allID, name: L.t("common.all"), kind: kind)
    }

    /// Bu kategori "Tümü" mü? Sayı etiketi bu durumda gösterilmez.
    var isAll: Bool { id == Self.allID }
}
