import SwiftUI

/// Canlı TV liste satırı.
///
/// Kanalların ayırt edici öğeleri vardır: logo (poster değil), varsa "şimdi /
/// sırada" bilgisi ve yayın ilerleme çubuğu. Bu yüzden film satırından ayrıdır.
///
/// Satıra dokunmak kanalı **hemen oynatır**; yayın akışına (EPG) gitmek için
/// sağdaki liste simgesi ya da uzun basma kullanılır. Bu ayrım bilinçlidir:
/// kullanıcıların çoğu kanal listesinde tek dokunuşla izlemeye başlamayı bekler.
struct ChannelRow: View {

    let channel: Channel
    /// Şu an yayında olan program (varsa).
    let now: EPGProgram?
    /// Sıradaki program (varsa).
    let next: EPGProgram?

    let isFavorite: Bool
    var isCurrent: Bool = false

    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    /// Yayın akışı (EPG) düğmesi gösterilsin mi? Gösterildiğinde düğme,
    /// kanalı değer olarak taşıyan bir `NavigationLink`'tir; gidilecek ekran
    /// üstteki yığında `navigationDestination(for: Channel.self)` ile tanımlanır.
    var showsGuideButton: Bool = false

    var body: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            Button(action: onSelect) {
                HStack(spacing: Theme.Metrics.rowSpacing) {
                    RemoteImage.channelLogo(channel.imageURL, title: channel.title)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(channel.title)
                                .font(Theme.Fonts.rowTitle)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)

                            if isCurrent {
                                BadgeLabel(text: L.t("live.badge.live"), style: .live)
                            } else if channel.hasArchive {
                                BadgeLabel(text: L.t("live.badge.archive"), style: .neutral)
                            }
                        }

                        epgLine
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsGuideButton {
                NavigationLink(value: channel) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L.t("live.guide.title")))
            }

            FavoriteStarButton(isFavorite: isFavorite, action: onToggleFavorite)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 8)
    }

    /// EPG varsa "20:00 · Ana Haber" biçiminde tek satır bilgi gösterilir.
    @ViewBuilder
    private var epgLine: some View {
        if let now {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Format.timeFormatter.string(from: now.start))
                        .font(Theme.Fonts.numeric)
                        .foregroundStyle(Theme.accent)
                    Text(now.title)
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                ThinProgressBar(value: now.progress)
                    .frame(maxWidth: 180)
            }
        } else if let category = channel.categoryName {
            Text(category)
                .font(Theme.Fonts.rowSubtitle)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        } else if let next {
            Text(L.f("live.nextItem", next.title))
                .font(Theme.Fonts.rowSubtitle)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }
}
