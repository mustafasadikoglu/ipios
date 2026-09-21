import SwiftUI

/// Uzak görsel (kanal logosu, poster) için ortak gösterim.
///
/// Neden `AsyncImage` sarmalayıcısı: listelerde yüzlerce satır olabilir ve her
/// satır için ayrı bir yükleme/hata/yer tutucu mantığı yazmak dağınıklık
/// yaratır. Burada tek yerde toplanır; ayrıca görsel yüklenemezse gösterilecek
/// yer tutucu (baş harfler) tutarlı olur.
struct RemoteImage: View {

    enum Shape {
        /// Kanal logoları: kare, zeminde hafif açık.
        case logo
        /// Film/dizi posterleri: 2:3 oranında dikdörtgen.
        case poster
        /// Izgara dışı serbest kullanım: köşe yarıçapı verilir.
        case flex(cornerRadius: CGFloat)
    }

    let url: URL?
    /// Görsel yokken gösterilecek metin (genelde başlık).
    let placeholderText: String
    var shape: Shape = .logo

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.15))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Theme.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.surface)
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.surface
            Text(initials)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(2)
        }
    }

    /// Başlıktan en fazla iki harflik kısaltma üretir.
    private var initials: String {
        let words = placeholderText
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    private var cornerRadius: CGFloat {
        switch shape {
        case .logo: return Theme.Metrics.posterRadius
        case .poster: return Theme.Metrics.posterRadius
        case .flex(let radius): return radius
        }
    }

    private var size: CGFloat {
        switch shape {
        case .logo: return Theme.Metrics.logoSize
        case .poster: return 120
        case .flex: return Theme.Metrics.logoSize
        }
    }
}

// MARK: - Hazır boyutlar

extension RemoteImage {
    /// Kanal listesi için sabit kare logo.
    static func channelLogo(_ url: URL?, title: String) -> some View {
        RemoteImage(url: url, placeholderText: title, shape: .logo)
            .frame(width: Theme.Metrics.logoSize, height: Theme.Metrics.logoSize)
            .background(Theme.surface)
    }

    /// Poster: genişlik verilir, yükseklik 2:3 oranından hesaplanır.
    static func poster(_ url: URL?, title: String, width: CGFloat) -> some View {
        RemoteImage(url: url, placeholderText: title, shape: .poster)
            .frame(width: width, height: width / Theme.Metrics.posterAspect)
            .background(Theme.surface)
    }
}
