#if DEBUG
import SwiftUI

/// Xcode Canvas için örnek veri ve önizleme galerisi.
///
/// Neden tek bir yerde: örnek veriler daha önce her modelin kendi dosyasında
/// (`Movie.previews`, `Channel.previews` …) duruyordu. Bunun iki sakıncası
/// vardı. Birincisi, hiçbiri kullanılmıyordu — projede tek bir `#Preview`
/// yoktu, yani dosyalarda ölü kod olarak kalıyorlardı. İkincisi, önizleme
/// metinleri modele gömülüydü; önizleme ekranda gerçek bir arayüz gösterdiği
/// için bu metinler de kullanıcıya görünür ve kural gereği
/// `Localizable.strings` içinden gelmelidir.
///
/// Buradaki her şey `#if DEBUG` içindedir: örnek veri son uygulamaya hiç
/// girmez, dolayısıyla ikili boyutu da etkilemez.
enum PreviewData {

    /// Örnek kaynak kimliği. Aynı önizleme içindeki tüm içerik bu kimliği
    /// paylaşır ki favori/ilerleme gibi kaynak bağımlı veriler tutarlı olsun.
    static let sourceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

    static let categories: [Category] = [
        Category(id: "all", name: L.t("common.all"), kind: .live, order: 0, itemCount: nil),
        Category(id: "1", name: L.t("preview.category.live"), kind: .live, order: 1, itemCount: 42),
        Category(id: "2", name: L.t("preview.category.movie"), kind: .movie, order: 2, itemCount: 128),
        Category(id: "3", name: L.t("preview.category.series"), kind: .series, order: 3, itemCount: 17)
    ]

    static let channels: [Channel] = [
        Channel(
            id: "101",
            sourceID: sourceID,
            title: L.t("preview.channel.1"),
            imageURL: URL(string: "https://example.com/logo/101.png"),
            streamURL: URL(string: "http://example.com/live/demo/101.m3u8")!,
            categoryID: "1",
            categoryName: L.t("preview.category.live"),
            hasArchive: true,
            epgChannelID: "101",
            order: 0
        ),
        Channel(
            id: "102",
            sourceID: sourceID,
            title: L.t("preview.channel.2"),
            imageURL: URL(string: "https://example.com/logo/102.png"),
            streamURL: URL(string: "http://example.com/live/demo/102.m3u8")!,
            categoryID: "1",
            categoryName: L.t("preview.category.live"),
            order: 1
        ),
        Channel(
            id: "103",
            sourceID: sourceID,
            title: L.t("preview.channel.3"),
            imageURL: URL(string: "https://example.com/logo/103.png"),
            streamURL: URL(string: "http://example.com/live/demo/103.m3u8")!,
            categoryID: "1",
            categoryName: L.t("preview.category.live"),
            hasArchive: true,
            order: 2
        )
    ]

    static let movies: [Movie] = [
        Movie(
            id: "501",
            sourceID: sourceID,
            title: L.t("preview.movie.1"),
            imageURL: URL(string: "https://example.com/poster/501.jpg"),
            streamURL: URL(string: "http://example.com/movie/demo/501.mp4")!,
            categoryID: "2",
            categoryName: L.t("preview.category.movie"),
            plot: L.t("preview.movie.plot"),
            year: "2024",
            durationSeconds: 7080,
            rating: "13+",
            genre: L.t("preview.movie.genre")
        )
    ]

    static let series: [Series] = [
        Series(
            id: "901",
            sourceID: sourceID,
            title: L.t("preview.series.1"),
            imageURL: URL(string: "https://example.com/poster/901.jpg"),
            categoryID: "3",
            categoryName: L.t("preview.category.series"),
            plot: L.t("preview.series.plot"),
            year: "2023",
            rating: "16+",
            genre: L.t("preview.movie.genre")
        )
    ]

    /// Şu an yayında olan ve sıradaki programı üretir; böylece önizlemede
    /// "CANLI" rozeti ve ilerleme çubuğu da gerçekçi görünür.
    static var programs: [EPGProgram] {
        let now = Date()
        return [
            EPGProgram(
                id: "p1",
                channelID: "101",
                title: L.t("preview.epg.1"),
                subtitle: nil,
                description: L.t("preview.epg.1.detail"),
                start: now.addingTimeInterval(-900),
                end: now.addingTimeInterval(1800),
                category: nil
            ),
            EPGProgram(
                id: "p2",
                channelID: "101",
                title: L.t("preview.epg.2"),
                subtitle: nil,
                description: L.t("preview.epg.2.detail"),
                start: now.addingTimeInterval(1800),
                end: now.addingTimeInterval(5400),
                category: nil
            )
        ]
    }
}

/// Ortak bileşenlerin ve kartların tek ekranda toplandığı önizleme.
///
/// Amaç, tasarım sistemindeki bir değişikliğin (renk, boşluk, yazı boyutu)
/// tüm bileşenleri nasıl etkilediğini tek bakışta görebilmek.
///
/// - Note: `#Preview` makrosu yerine `PreviewProvider` kullanılır: makro
///   yalnızca iOS 17+ ile derlenir, bu projenin hedefi ise iOS 16.0'dır.
///   `PreviewProvider` iOS 13'ten beri desteklenir.
struct ComponentGalleryPreview: PreviewProvider {
    static var previews: some View {
        ScrollView {
            // Dış boşluk verilmez: `SectionHeader`, `ChannelRow` ve
            // `CategoryChipBar` kendi yatay boşluklarını
            // (`Theme.Metrics.gutter`) taşır. Dıştan da boşluk vermek
            // kenarları iki kat içeri iter ve önizleme, gerçek ekrandan
            // farklı görünür.
            VStack(alignment: .leading, spacing: 20) {

                SectionHeader(title: L.t("preview.section.categories"))

                CategoryChipBar(
                    categories: PreviewData.categories,
                    selection: .constant("1")
                )

                SectionHeader(title: L.t("preview.section.cards"))

                HStack(alignment: .top, spacing: Theme.Metrics.cardRadius) {
                    ForEach(PreviewData.movies) { movie in
                        PosterCard(
                            title: movie.title,
                            subtitle: movie.durationText,
                            imageURL: movie.imageURL,
                            badge: BadgeLabel(text: L.t("live.badge.archive"))
                        )
                    }
                    ForEach(PreviewData.series) { item in
                        PosterCard(
                            title: item.title,
                            subtitle: item.year,
                            imageURL: item.imageURL,
                            badge: BadgeLabel(text: L.t("live.badge.live"), style: .live)
                        )
                    }
                }
                .padding(.horizontal, Theme.Metrics.gutter)

                SectionHeader(
                    title: L.t("preview.section.models"),
                    subtitle: L.f("sources.synced.value", Format.relative(Date()))
                )

                ForEach(PreviewData.channels) { channel in
                    ChannelRow(
                        channel: channel,
                        now: PreviewData.programs.first,
                        next: PreviewData.programs.last,
                        isFavorite: channel.id == "101",
                        onSelect: {},
                        onToggleFavorite: {}
                    )
                }

                // `LoadingView`, `EmptyStateView` ve `ErrorStateView`
                // bulundukları alanı kaplayacak şekilde tasarlanmıştır
                // (ekran ortası). Kaydırmalı bir listede sınırsız yükseklik
                // isterlerse düzen bozulur; bu yüzden burada sabit bir
                // yükseklik verilir.
                SectionHeader(title: L.t("preview.section.loading"))
                LoadingView()
                    .frame(height: 90)

                SectionHeader(title: L.t("preview.section.empty"))
                EmptyStateView(
                    icon: "star",
                    title: L.t("favorites.empty.title"),
                    message: L.t("favorites.empty.message")
                )
                .frame(height: 200)

                SectionHeader(title: L.t("preview.section.error"))
                ErrorStateView(message: L.t("preview.error.message")) {}
                    .frame(height: 140)
            }
            .padding(.vertical, Theme.Metrics.gutter)
        }
        .screenBackground()
        .preferredColorScheme(.dark)
    }
}

/// Boş durum bileşeni ayrı önizlenir: tüm alanı kaplar ve kaydırmalı bir
/// listede diğer bileşenlerle birlikte gösterilemez.
struct EmptyStatePreview: PreviewProvider {
    static var previews: some View {
        EmptyStateView(
            icon: "tv.slash",
            title: L.t("preview.empty.title"),
            message: L.t("preview.empty.message"),
            actionTitle: L.t("common.retry")
        ) {}
        .screenBackground()
        .preferredColorScheme(.dark)
    }
}
#endif
