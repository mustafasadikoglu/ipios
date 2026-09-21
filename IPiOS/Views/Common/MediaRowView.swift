import SwiftUI

/// Liste satırlarında gösterilecek ortak eylemler.
///
/// Neden yalnızca eylemler: satırların düzeni türe göre değişir (kanalda logo
/// ve EPG, filmde poster ve süre). Bu yüzden ortak olan tek şey davranıştır.
struct MediaRowActions {

    /// Favori durumu (yıldız gösterilsin mi?).
    var isFavorite: Bool = false
    /// Favori yıldızı gösterilsin mi? (Bölümler için `false`.)
    var showsFavoriteButton: Bool = false

    /// Satıra dokunma. `nil` ise satır tıklanabilir olmaz — dizi satırları
    /// kendi `NavigationLink`'i içinde kullanıldığında bu tercih edilir:
    /// bağlantı etiketinin içine iç içe düğme koymak dokunuşu belirsizleştirir.
    var onSelect: (() -> Void)?
    var onToggleFavorite: () -> Void = {}
}

/// Kanal / film / bölüm için ortak sağ taraf: yıldız ve favori durumu.
struct FavoriteStarButton: View {

    let isFavorite: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isFavorite ? Theme.accent : Theme.textTertiary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(L.t(isFavorite ? "favorites.remove" : "favorites.add"))
        )
    }
}

/// Posterli liste satırı (filmler, diziler, bölümler).
struct MediaRow: View {

    let title: String
    let subtitle: String?
    let imageURL: URL?
    var badge: BadgeLabel?
    /// İzleme ilerlemesi (0...1); 0 ise gösterilmez.
    var progress: Double = 0
    /// "İzlemeye devam et" satırlarında kalan süre gibi ek metin.
    var trailingText: String?
    var actions: MediaRowActions

    var body: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            if let onSelect = actions.onSelect {
                Button(action: onSelect) {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label
            }

            if let trailingText {
                Text(trailingText)
                    .font(Theme.Fonts.numeric)
                    .foregroundStyle(Theme.textTertiary)
            }

            // Yıldız, dokunulabilir içeriğin dışında kalır; içeride olsaydı
            // satıra gitmek isteyen dokunuşla çakışırdı.
            if actions.showsFavoriteButton {
                FavoriteStarButton(isFavorite: actions.isFavorite, action: actions.onToggleFavorite)
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 8)
    }

    private var label: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            RemoteImage.poster(imageURL, title: title, width: 46)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let badge { badge }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                if progress > 0 {
                    ThinProgressBar(value: progress)
                        .frame(maxWidth: 160)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
