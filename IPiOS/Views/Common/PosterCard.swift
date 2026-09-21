import SwiftUI

/// Izgara görünümünde tek bir poster kartı (film veya dizi).
///
/// Neden ortak: film ve dizi ızgaraları aynı kartı kullanır. Ayrı ayrı
/// yazılsalardı poster oranı, yazı boyutu ve favori düğmesinin yeri zamanla
/// birbirinden ayrışırdı.
///
/// Kart genişliği dışarıdan verilmez: bulunduğu sütunun genişliğini doldurur.
/// Yatay şeritlerde ise çağıran taraf `.frame(width:)` ile sabitler.
struct PosterCard: View {

    let title: String
    let subtitle: String?
    let imageURL: URL?

    var badge: BadgeLabel?
    /// İzleme ilerlemesi (0...1); 0 ise gösterilmez.
    var progress: Double = 0

    var isFavorite: Bool = false
    var showsFavoriteButton: Bool = false

    /// Karta dokunma. `nil` ise kart kendi düğmesini kurmaz; çağıran taraf
    /// kartı bir `NavigationLink` içine alır. İç içe düğme koymamak için
    /// gerekli: bağlantı etiketinin içindeki düğme dokunuşu yutar ve
    /// gezinti çalışmaz.
    var onSelect: (() -> Void)?
    var onToggleFavorite: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
                // Favori yıldızı bilinçli olarak düğmenin/bağlantının DIŞINDA
                // durur. İçeride olsaydı iki sorun çıkardı: iç içe denetimler
                // dokunuşu belirsizleştirir ve `NavigationLink` etiketindeki
                // düğme hiç dokunuş almaz.
                .overlay(alignment: .bottomTrailing) {
                    if showsFavoriteButton {
                        FavoriteStarButton(isFavorite: isFavorite, action: onToggleFavorite)
                            .background(Circle().fill(Theme.background.opacity(0.6)))
                            .padding(4)
                    }
                }

            Text(title)
                .font(Theme.Fonts.rowSubtitle.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.Fonts.numeric)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var poster: some View {
        GeometryReader { proxy in
            posterContent(width: proxy.size.width)
        }
        .aspectRatio(Theme.Metrics.posterAspect, contentMode: .fit)
    }

    @ViewBuilder
    private func posterContent(width: CGFloat) -> some View {
        if let onSelect {
            Button(action: onSelect) {
                artwork(width: width)
            }
            .buttonStyle(.plain)
        } else {
            artwork(width: width)
        }
    }

    private func artwork(width: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            RemoteImage.poster(imageURL, title: title, width: width)

            if let badge {
                badge.padding(6)
            }
        }
        .overlay(alignment: .bottom) {
            if progress > 0 {
                ThinProgressBar(value: progress)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
        }
        .contentShape(Rectangle())
    }
}
