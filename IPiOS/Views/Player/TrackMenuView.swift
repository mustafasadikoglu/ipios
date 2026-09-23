import SwiftUI

/// Oynatıcıda ses ve altyazı izi seçme menüsü.
///
/// **Neden oynatıcının içinde bir sayfa değil, üstte bir kart:** oynatıcı tam
/// ekran bir kapaktır (`fullScreenCover`). İçinde başka bir sayfa açmak ikinci
/// bir sunum katmanı doğurur ve kullanıcı sesi değiştirirken **görüntüyü
/// kaybeder**. İz seçimi görüntünün üstünde, onu kapatmadan yapılmalıdır.
///
/// **Neden liste yalnızca `PlaybackTrack` taşır:** libvlc'nin iz nesneleri her
/// okumada yeniden üretilir (bkz. `PlaybackTrack`). Bu görünüm yalnızca kararlı
/// kimliklerle çalışır ve seçimi kimlikle bildirir; motora indeks geçmez.
struct TrackMenuView: View {

    let tracks: PlaybackTrackSet
    /// Ses izi seçildi. Kimlik motora `trackId` olarak gider.
    let onSelectAudio: (String) -> Void
    /// Altyazı izi seçildi.
    let onSelectSubtitle: (String) -> Void
    /// Altyazı kapatıldı.
    let onDisableSubtitles: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    if tracks.hasAudioChoice {
                        section(title: L.t("player.tracks.audioSection")) {
                            ForEach(tracks.audio) { track in
                                row(
                                    label: audioLabel(for: track),
                                    detail: track.language,
                                    isSelected: track.id == tracks.selectedAudioID
                                ) {
                                    onSelectAudio(track.id)
                                }
                            }
                        }
                    }

                    if tracks.hasSubtitleChoice {
                        section(title: L.t("player.tracks.subtitleSection")) {
                            // "Kapalı" her zaman ilk satırdır ve altyazıyı
                            // kapatmak geçerli bir seçimdir — hata değil.
                            row(
                                label: L.t("player.tracks.off"),
                                detail: nil,
                                isSelected: tracks.selectedSubtitleID == nil
                            ) {
                                onDisableSubtitles()
                            }

                            ForEach(tracks.subtitles) { track in
                                row(
                                    label: subtitleLabel(for: track),
                                    detail: track.language,
                                    isSelected: track.id == tracks.selectedSubtitleID
                                ) {
                                    onSelectSubtitle(track.id)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            // **Neden hesaplanan bir yükseklik:** `ScrollView` önerilen
            // yüksekliği sonuna kadar doldurur. Yalnızca `maxHeight: 320`
            // verilseydi iki satırlık bir menü de 320 pt'lik boş bir kart olarak
            // çizilirdi. Bu yüzden üst sınır **içeriğe göre** hesaplanır ve
            // yalnızca taşma durumunda 320 pt'ye kırpılır.
            .frame(maxHeight: estimatedHeight)
        }
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(
            cornerRadius: Theme.Metrics.cardRadius,
            style: .continuous
        ))
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Başlık

    private var header: some View {
        HStack(spacing: 8) {
            Text(L.t("player.tracks.title"))
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .accessibilityLabel(Text(L.t("common.close")))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Bölüm

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(Theme.Fonts.badge)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
            content()
        }
    }

    // MARK: - Satır

    private func row(
        label: String,
        detail: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Seçim işareti sabit genişlikte bir kutuda durur: işaret
                // olmayan satırlarda da aynı boşluk kalır, metinler hizalanır.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : .white.opacity(0.35))
                    .frame(width: 20)

                Text(label)
                    .font(Theme.Fonts.rowSubtitle.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let detail, !detail.isEmpty {
                    Text(detail.uppercased())
                        .font(Theme.Fonts.badge)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Yükseklik

    /// Menünün içeriğe göre üst sınırı.
    ///
    /// Sabit değerler burada kabul edilebilir: satır ve başlık yükseklikleri
    /// yazı tipi sistemiyle birlikte sabittir ve dinamik tür (Dynamic Type) bu
    /// ekranda kullanılmaz — oynatıcı kontrol katmanı da sabit ölçülerle
    /// çizilir. Amaç piksel isabeti değil, **kısa içerikte boş kart
    /// çizilmemesi**dir.
    private var estimatedHeight: CGFloat {
        let rowHeight: CGFloat = 38
        let sectionHeader: CGFloat = 26
        let verticalPadding: CGFloat = 12
        let maximum: CGFloat = 320

        var total = verticalPadding
        if tracks.hasAudioChoice {
            total += sectionHeader + CGFloat(tracks.audio.count) * rowHeight
        }
        if tracks.hasSubtitleChoice {
            // "Kapalı" satırı her zaman bir fazla.
            total += sectionHeader + CGFloat(tracks.subtitles.count + 1) * rowHeight
        }
        return min(total, maximum)
    }

    // MARK: - Etiketler

    /// Ses izinin etiketi.
    ///
    /// Gömülü ses izlerinde libvlc `trackName` alanını **boş** bırakır; bu
    /// durumda kullanıcıya "Ses 2" gibi numaralı bir etiket gösterilir. Aksi
    /// hâlde boş satırlar görünürdü ve kullanıcı hangi izi seçtiğini bilemezdi.
    private func audioLabel(for track: PlaybackTrack) -> String {
        let name = track.name.trimmingCharacters(in: .whitespaces)
        guard name.isEmpty else { return name }
        return L.f("player.tracks.audioOrdinal", track.displayOrdinal)
    }

    private func subtitleLabel(for track: PlaybackTrack) -> String {
        let name = track.name.trimmingCharacters(in: .whitespaces)
        guard name.isEmpty else { return name }
        return L.f("player.tracks.subtitleOrdinal", track.displayOrdinal)
    }
}
