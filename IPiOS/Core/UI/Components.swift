import SwiftUI

/// Ekranlar arasında paylaşılan küçük arayüz parçaları.

// MARK: - Durum görünümleri

/// Liste boşken gösterilen yer tutucu.
struct EmptyStateView: View {

    let icon: String
    let title: String
    let message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.textTertiary)

            Text(title)
                .font(Theme.Fonts.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(Theme.Fonts.rowSubtitle)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 420)
        .padding(Theme.Metrics.gutter * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Yükleme göstergesi (tam ekran).
struct LoadingView: View {
    var text: String = L.t("common.loading")

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Theme.accent)
            Text(text)
                .font(Theme.Fonts.rowSubtitle)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hata görünümü: mesaj ve (varsa) yeniden deneme.
struct ErrorStateView: View {

    let message: String
    var retryTitle: String = L.t("common.retry")
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Theme.liveRed)

            Text(message)
                .font(Theme.Fonts.rowSubtitle)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 420)
        .padding(Theme.Metrics.gutter * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Buton stilleri

/// Dolu, marka renginde ana eylem düğmesi.
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.rowTitle)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(isEnabled ? Theme.accent : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - Etiketler

/// Küçük bilgi etiketi ("CANLI", "Arşiv", "13+").
struct BadgeLabel: View {

    enum Style {
        case accent
        case live
        case neutral

        var foreground: Color {
            switch self {
            case .accent: return Theme.accent
            case .live: return .white
            case .neutral: return Theme.textSecondary
            }
        }

        var background: Color {
            switch self {
            case .accent: return Theme.accent.opacity(0.18)
            case .live: return Theme.liveRed
            case .neutral: return Theme.elevated
            }
        }
    }

    let text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .font(Theme.Fonts.badge)
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(style.background)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Kategori seçimi için yatay kaydırılabilir etiket çubuğu.
struct CategoryChipBar: View {

    let categories: [Category]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    let isSelected = category.id == selection
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selection = category.id }
                    } label: {
                        Text(label(for: category))
                            .font(Theme.Fonts.rowSubtitle.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isSelected ? Theme.accent : Theme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, 6)
        }
    }

    /// "Tümü" kategorisinde sayı gösterilmez; diğerlerinde varsa eklenir.
    ///
    /// Ayırıcı işaret de dâhil olmak üzere tüm metin `Localizable.strings`
    /// içinden gelir; kodda yalnızca `" · "` gibi bir sabit bırakmak, çeviri
    /// dosyasında değiştirilemeyen gizli bir kullanıcı metni oluştururdu.
    private func label(for category: Category) -> String {
        guard let count = category.itemCount, !category.isAll else { return category.name }
        return category.name + L.f("common.count.suffix", count)
    }
}

/// Yatay bölüm başlığı ("İzlemeye Devam Et" gibi).
struct SectionHeader: View {

    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Fonts.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Fonts.numeric)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
    }
}

// MARK: - İlerleme

/// İnce ilerleme çubuğu (izleme yüzdesi, yayın ilerlemesi).
struct ThinProgressBar: View {

    /// `0...1`
    let value: Double
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.progressTrack)
                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: Theme.Metrics.progressHeight)
        .clipShape(Capsule())
    }
}
