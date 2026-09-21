import SwiftUI

/// Uygulamanın görsel dili: renk, tipografi ve ölçü token'ları.
///
/// Neden gerekli: aynı boşluğu ya da rengi onlarca dosyada elle yazmak,
/// uygulamanın ekranlar arasında tutarsız görünmesine yol açar. Tüm görsel
/// kararlar burada toplanır; ekranlar yalnızca `Theme.*` kullanır.
///
/// Tema koyu (dark) tabanlıdır: uygulama ağırlıklı olarak video oynatır ve
/// poster/logo görselleri koyu zemin üzerinde daha iyi okunur.
enum Theme {

    // MARK: - Renkler

    /// En alt katman: sayfa arka planı.
    static let background = Color(hex: 0x0B0D12)
    /// Kart ve liste satırı zemini.
    static let surface = Color(hex: 0x151922)
    /// Sayfa üstünde yüzen yüzeyler (oynatıcı kontrolleri, sheet).
    static let elevated = Color(hex: 0x1E2430)
    /// İnce ayırıcı çizgi.
    static let separator = Color(hex: 0x262D3A)

    static let textPrimary = Color(hex: 0xF2F4F8)
    static let textSecondary = Color(hex: 0x99A2B3)
    static let textTertiary = Color(hex: 0x69717F)

    /// Marka rengi. Yalnızca gerçekten dikkat çekmesi gereken öğelerde kullanılır.
    static let accent = Color(hex: 0x7C5CFF)
    /// Canlı yayın göstergesi.
    static let liveRed = Color(hex: 0xFF3B5C)
    /// İzleme / yayın ilerlemesi.
    static let progressTrack = Color(hex: 0x2A3140)

    // MARK: - Tipografi

    enum Fonts {
        /// Ekran başlığı (navigation title).
        static let screenTitle = Font.system(size: 28, weight: .bold)
        /// Bölüm başlığı ("Devam Et", "Sezonlar").
        static let sectionTitle = Font.system(size: 20, weight: .semibold)
        /// Liste satırı ana metni.
        static let rowTitle = Font.system(size: 16, weight: .semibold)
        /// Liste satırı alt metni.
        static let rowSubtitle = Font.system(size: 13, weight: .regular)
        /// Küçük etiket ("CANLI", "13+", "2024").
        static let badge = Font.system(size: 11, weight: .bold)
        /// Süre ve saat gibi sayısal metinler; hizalı görünmesi için sabit genişlik.
        static let numeric = Font.system(size: 12, weight: .medium).monospacedDigit()
    }

    // MARK: - Ölçüler

    enum Metrics {
        /// Yatay sayfa kenar boşluğu.
        static let gutter: CGFloat = 16
        static let cardRadius: CGFloat = 12
        static let posterRadius: CGFloat = 8
        static let rowSpacing: CGFloat = 12
        /// Kanal logosu kutusu.
        static let logoSize: CGFloat = 52
        /// Poster en/boy oranı (2:3).
        static let posterAspect: CGFloat = 2.0 / 3.0
        /// Satır ilerleme çubuğu yüksekliği.
        static let progressHeight: CGFloat = 3
    }
}

// MARK: - Yardımcılar

extension Color {
    /// `Color(hex: 0x7C5CFF)` biçiminde renk üretir.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// Sayfa zemini ve kenar boşluklarını tek çağrıda uygular.
    func screenBackground() -> some View {
        self
            .background(Theme.background.ignoresSafeArea())
    }
}
