import SwiftUI

/// İlk açılışta gösterilen yasal uyarı.
///
/// Uygulama hiçbir yayın içeriği barındırmaz; yalnızca kullanıcının eklediği
/// kaynağı oynatır. Bu nedenle kullanıcı, sorumluluğun kendisinde olduğunu
/// açıkça kabul etmeden uygulamayı kullanamaz.
///
/// Aynı metin kaynak ekleme ekranında da kısaca hatırlatılır.
struct LegalView: View {

    /// "Okudum, kabul ediyorum" seçildiğinde çağrılır.
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing * 1.5) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(Theme.accent)
                        .padding(.bottom, 4)

                    Text(L.t("legal.title"))
                        .font(Theme.Fonts.screenTitle)
                        .foregroundStyle(Theme.textPrimary)

                    Text(L.t("legal.intro"))
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textSecondary)

                    Text(L.t("legal.body"))
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, Theme.Metrics.gutter * 1.5)
                .padding(.top, Theme.Metrics.gutter * 2)
                .padding(.bottom, Theme.Metrics.gutter * 3)
                .frame(maxWidth: .infinity)
            }

            // Kabul düğmesi içeriğin altında sabit durur: uzun metni
            // kaydırırken eylem hep erişilebilir kalır.
            VStack(spacing: 8) {
                Button(L.t("legal.accept"), action: onAccept)
                    .buttonStyle(PrimaryButtonStyle())

                Text(L.t("legal.decline"))
                    .font(Theme.Fonts.rowSubtitle)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, Theme.Metrics.gutter * 1.5)
            .padding(.top, Theme.Metrics.rowSpacing)
            .padding(.bottom, Theme.Metrics.gutter)
            .background(
                Theme.background
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 1)
                    }
            )
        }
        .screenBackground()
    }
}
