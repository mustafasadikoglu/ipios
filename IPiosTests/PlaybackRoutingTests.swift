import XCTest
@testable import IPiOS

/// Oynatma adresi seçiminin ve Xtream uzantı normalleştirmesinin kurallarını
/// doğrular.
///
/// Neden gerekli: canlı yayınların oynatılmamasının kök nedeni bu iki kuraldı.
/// Xtream panelleri canlı yayın için `stream_type = "ts"` bildirir ve
/// `/live/<user>/<pass>/<id>.ts` ham bir MPEG-TS akışıdır; `AVPlayer` bu
/// konteyneri çözemez ve hata vermeden siyah ekranda kalır. Yalnızca HLS
/// paketlemesi (`.m3u8`) oynatılabilir. Bu kurallar sessizce geri alınırsa
/// kusur yeniden ortaya çıkar ve yalnızca gerçek bir sağlayıcıyla denenerek
/// fark edilebilir.
final class PlaybackRoutingTests: XCTestCase {

    // MARK: - Yardımcılar

    /// Testte sahte bir tip yazmak yerine üretimdeki `AnyMediaItem` kullanılır:
    /// `playbackCandidates` gerçekte bu tipi görür, dolayısıyla adres üretimi
    /// sırasında tip kaynaklı bir sapma da bu testte ortaya çıkar.
    private func item(_ url: String) -> AnyMediaItem {
        AnyMediaItem(
            id: "1",
            title: "Örnek",
            imageURL: nil,
            streamURL: URL(string: url)!,
            sourceID: UUID(),
            kind: .live
        )
    }

    private let base = "http://cdn.example.com/live/user/pass/123"

    // MARK: - Aday sırası

    /// Canlı yayında HLS birincil, ham TS yedek olmalı.
    @MainActor
    func testLiveCandidatesPreferHLSThenTS() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("\(base).m3u8"), isLive: true
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            ["\(base).m3u8", "\(base).ts"],
            "Canlı yayında önce HLS denenmeli, ham TS yalnızca yedek olmalı"
        )
    }

    /// Kaynak `.ts` bildirse bile HLS önce denenmeli: asıl kusur buydu.
    @MainActor
    func testLiveCandidatesLiftRawTransportStreamToHLS() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("\(base).ts"), isLive: true
        )
        XCTAssertEqual(candidates.first?.absoluteString, "\(base).m3u8")
        XCTAssertEqual(candidates.count, 2)
    }

    /// VOD'da asıl adres **her zaman** ilk sırada denenir; sağlayıcının
    /// bildirdiği biçim destekleniyorsa ona öncelik verilir.
    @MainActor
    func testVODAlwaysTriesDeclaredAddressFirst() {
        for ext in ["mp4", "mov", "m2ts", "mkv", "avi", "webm"] {
            let url = "http://cdn.example.com/movie/user/pass/9.\(ext)"
            let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
            XCTAssertEqual(candidates.first?.absoluteString, url, "\(ext) ilk aday olmalı")
        }
    }

    /// `mp4` her durumda denenir: Xtream VOD'un standart biçimidir ve
    /// sağlayıcı `container_extension` alanında farklı bir şey bildirse bile
    /// dosya çoğu zaman `.mp4` olarak da çalışır.
    @MainActor
    func testVODAlwaysIncludesMP4Candidate() {
        for ext in ["mkv", "avi", "webm", "m2ts", "mov", "flv", "wmv"] {
            let url = "http://cdn.example.com/movie/user/pass/9.\(ext)"
            let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
            XCTAssertTrue(
                candidates.contains { $0.pathExtension == "mp4" },
                "\(ext) için mp4 yedeği bulunmalı"
            )
        }
    }

    /// mp4 zaten asıl adresteyse yedek olarak **tekrar eklenmemeli**.
    @MainActor
    func testVODDoesNotDuplicateMP4WhenItIsPrimary() {
        let url = "http://cdn.example.com/movie/user/pass/9.mp4"
        let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
        XCTAssertEqual(
            candidates.filter { $0.pathExtension == "mp4" }.count,
            1,
            "asıl adres mp4 ise ikinci kez eklenmemeli"
        )
    }

    /// VOD'da HLS **en son** çare olarak denenir.
    ///
    /// Xtream VOD'u standart olarak HLS ile sunmaz; bu yüzden `.m3u8` birincil
    /// yedek değildir. Ancak VOD'u HLS olarak da paketleyen paneller vardır ve
    /// bir deneme daha yapmak, kullanıcıya kesin bir hata göstermekten iyidir.
    @MainActor
    func testVODTriesHLSAsLastResortOnly() {
        let url = "http://cdn.example.com/movie/user/pass/9.mkv"
        let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            [
                url,
                "http://cdn.example.com/movie/user/pass/9.mp4",
                "http://cdn.example.com/movie/user/pass/9.m3u8"
            ],
            "sıra: asıl → mp4 → m3u8 olmalı"
        )
    }

    /// VOD'da tek adayla yetinilmemeli: "canlı çalışıyor, film/dizi
    /// çalışmıyor" farkının kök nedeni buydu.
    ///
    /// Canlı yayında uzantıdan bağımsız olarak her zaman iki aday üretilir ve
    /// biri tutmazsa diğeri denenir. VOD'da yedek yalnızca çözülemeyen
    /// konteynerlerde üretiliyordu; sağlayıcı oynatılabilir görünen bir uzantı
    /// bildirdiğinde liste tek elemana düşüyor ve o adres tutmazsa kullanıcı
    /// doğrudan hata uyarısı görüyordu.
    @MainActor
    func testVODNeverReliesOnASingleCandidate() {
        for ext in ["mp4", "mov", "m2ts", "mkv", "avi", "webm", "flv"] {
            let url = "http://cdn.example.com/movie/user/pass/9.\(ext)"
            let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
            XCTAssertGreaterThan(
                candidates.count, 1,
                "\(ext) için yedek aday üretilmeli — tek adayla kalınmamalı"
            )
        }
    }

    /// Sorgu dizesi yedek adreslere de taşınmalı; düşerse sağlayıcı isteği
    /// reddeder.
    @MainActor
    func testVODFallbackPreservesQueryString() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("http://cdn.example.com/movie/user/pass/9.mkv?token=abc"),
            isLive: false
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            [
                "http://cdn.example.com/movie/user/pass/9.mkv?token=abc",
                "http://cdn.example.com/movie/user/pass/9.mp4?token=abc",
                "http://cdn.example.com/movie/user/pass/9.m3u8?token=abc"
            ]
        )
    }

    /// Yedek adres üretilirken kimlik bilgisinin kodlaması **aynen** korunmalı.
    ///
    /// Ölçülmüş kusur: uzantı değiştirme, çözülmüş yol üzerinden yapılıyordu.
    /// `URLComponents.path` ayarlayıcısı `/` karakterini kodlamaz; şifresinde
    /// eğik çizgi olan kullanıcıda asıl adreste `%2F` olarak duran karakter
    /// çözülüp ham `/` olarak geri yazılıyor, yol bir fazla parçaya bölünüyor
    /// ve kimlik yanlış okunuyordu. Kusur yalnızca **yedek** adreste görünür;
    /// asıl adres doğru kalır. Yani belirti "bazı filmler açılıyor, bazıları
    /// açılmıyor" olurdu.
    ///
    /// Not: burada akla ilk gelen "iki kez kodlama" (`%2540`) kusuru
    /// **yoktu** — o varsayım ölçülerek elendi, çünkü eski kod çözüp yeniden
    /// kodladığı için tur gidiş-dönüşü kararlıydı.
    @MainActor
    func testFallbackCandidatesPreserveEncodedPath() {
        let url = "http://cdn.example.com/movie/user/p%40ss/9.mkv"
        let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            [
                url,
                "http://cdn.example.com/movie/user/p%40ss/9.mp4",
                "http://cdn.example.com/movie/user/p%40ss/9.m3u8"
            ]
        )
        for candidate in candidates {
            XCTAssertFalse(
                candidate.absoluteString.contains("%25"),
                "yol iki kez kodlanmamalı: \(candidate.absoluteString)"
            )
        }
    }

    /// Eğik çizgi içeren kimlik bilgisi yedek adreste yol parçası sayısını
    /// **değiştirmemeli**. Bu, kusurun doğrudan testidir: bölünme olursa
    /// kullanıcı adı ile şifre arasına fazladan bir parça girer ve sağlayıcı
    /// isteği reddeder.
    @MainActor
    func testFallbackCandidatesDoNotSplitEncodedSlash() {
        let url = "http://cdn.example.com/movie/user/p%2Fa/9.mkv"
        let candidates = AVPlayerEngine.playbackCandidates(for: item(url), isLive: false)
        XCTAssertEqual(candidates.count, 3)
        for candidate in candidates {
            XCTAssertEqual(
                candidate.pathComponents.count,
                URL(string: url)!.pathComponents.count,
                "yol parça sayısı değişmemeli: \(candidate.absoluteString)"
            )
            XCTAssertTrue(
                candidate.absoluteString.contains("p%2Fa"),
                "kimlik kodlaması korunmalı: \(candidate.absoluteString)"
            )
        }
        XCTAssertEqual(
            candidates.last?.absoluteString,
            "http://cdn.example.com/movie/user/p%2Fa/9.m3u8"
        )
    }

    /// Canlı yayında da aynı kural geçerlidir: uzantı değişirken kimlik
    /// bilgilerinin kodlaması korunur.
    @MainActor
    func testLiveCandidatesPreserveEncodedPath() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("http://cdn.example.com/live/u/p%2Bw/7.ts"), isLive: true
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            [
                "http://cdn.example.com/live/u/p%2Bw/7.m3u8",
                "http://cdn.example.com/live/u/p%2Bw/7.ts"
            ]
        )
    }

    /// Üst dizinlerdeki nokta uzantı sanılmamalı: nokta yalnızca son parçanın
    /// içinde aranır. Aksi hâlde `/v1.2/movie/9` gibi bir adreste `9` yerine
    /// yanlış yerden kesilir.
    @MainActor
    func testExtensionIsSearchedOnlyInLastPathSegment() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("http://cdn.example.com/v1.2/movie/u/p/9.mkv"), isLive: false
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            [
                "http://cdn.example.com/v1.2/movie/u/p/9.mkv",
                "http://cdn.example.com/v1.2/movie/u/p/9.mp4",
                "http://cdn.example.com/v1.2/movie/u/p/9.m3u8"
            ],
            "üst dizindeki nokta adresi bozmamalı"
        )
    }

    /// Uzantısız adres için uydurma adres üretilmemeli.
    @MainActor
    func testCandidatesFallBackToPrimaryWhenExtensionIsMissing() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("\(base)"), isLive: true
        )
        XCTAssertEqual(candidates.map(\.absoluteString), [base])
    }

    /// Sorgu dizesi (jeton, oturum kimliği) korunmalı; düşerse sağlayıcı
    /// isteği reddeder.
    @MainActor
    func testCandidatesPreserveQueryString() {
        let candidates = AVPlayerEngine.playbackCandidates(
            for: item("\(base).m3u8?token=abc"), isLive: true
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            ["\(base).m3u8?token=abc", "\(base).ts?token=abc"]
        )
    }

    // MARK: - Xtream uzantı normalleştirmesi

    /// `ts` bilinçli olarak `m3u8`'e çevrilir; `AVPlayer` ham TS'i çözemez.
    func testTransportStreamHintNormalizesToHLS() {
        XCTAssertEqual(XtreamClient.normalizeExtension("ts"), "m3u8")
        XCTAssertEqual(XtreamClient.normalizeExtension("mpegts"), "m3u8")
        XCTAssertEqual(XtreamClient.normalizeExtension("m3u8"), "m3u8")
        XCTAssertEqual(XtreamClient.normalizeExtension("HLS"), "m3u8")
    }

    /// Oynatılabilir VOD uzantıları olduğu gibi kalmalı ve **HLS'e
    /// çevrilmemeli**. Bu kural bir kez bozulmuştu: normalleştirme tüm
    /// adresleri HLS'e zorluyordu, böylece film/dizi adresleri sağlayıcının
    /// sunmadığı bir yola dönüşüyor ve oynatma hiç başlamıyordu.
    func testVideoContainersArePreserved() {
        for ext in ["mp4", "mkv", "avi", "mov", "webm", "m2ts"] {
            XCTAssertEqual(XtreamClient.normalizeExtension(ext), ext, "\(ext) korunmalı")
        }
    }

    /// Uzantı bildirilmezse HLS varsayılır (güvenli taraf).
    func testMissingHintDefaultsToHLS() {
        XCTAssertEqual(XtreamClient.normalizeExtension(nil), "m3u8")
        XCTAssertEqual(XtreamClient.normalizeExtension(""), "m3u8")
    }

    /// Baştaki nokta temizlenir; `".mp4"` adres içinde `..mp4` üretmemeli.
    func testLeadingDotIsStripped() {
        XCTAssertEqual(XtreamClient.normalizeExtension(".mp4"), "mp4")
    }

    // MARK: - Yol parçası kodlaması

    /// Kimlik bilgileri akış adresinde **yolun içinde** taşınır ve
    /// kodlanmalıdır. `URLComponents.path` ayarlayıcısı alt sınırlayıcıları
    /// (`@`, `+`, `:`, `,`, `;`, `=`, `&`, `$`) kodlamaz; şifresinde bunlardan
    /// biri olan kullanıcıda yol sessizce bozulur. Ortaya çıkan tablo tam
    /// olarak şuydu: liste gelir, poster gelir, video hiç açılmaz.
    func testPathSegmentsEncodeSubDelimiters() {
        XCTAssertEqual(XtreamClient.percentEncodedPathSegment("a@b"), "a%40b")
        XCTAssertEqual(XtreamClient.percentEncodedPathSegment("a+b"), "a%2Bb")
        XCTAssertEqual(XtreamClient.percentEncodedPathSegment("a:b"), "a%3Ab")
        XCTAssertEqual(XtreamClient.percentEncodedPathSegment("a&b=c"), "a%26b%3Dc")
        XCTAssertEqual(XtreamClient.percentEncodedPathSegment("a;b,c"), "a%3Bb%2Cc")
        XCTAssertEqual(XtreamClient.percentEncodedPathSegment("a$b"), "a%24b")
    }

    /// Eğik çizgi kodlanmazsa yol ikiye bölünür ve adres bambaşka bir kaynağı
    /// işaret eder. Sessiz veri bozulmasının en tehlikeli biçimi budur.
    func testPathSegmentsEncodeSlashSoPathIsNotSplit() {
        XCTAssertFalse(XtreamClient.percentEncodedPathSegment("a/b").contains("/"))
        XCTAssertEqual(XtreamClient.percentEncodedPathSegment("a/b"), "a%2Fb")
    }

    /// Boşluk ve ASCII dışı (Türkçe) karakterler de kodlanmalı; aksi hâlde
    /// adres hiç kurulamaz.
    func testPathSegmentsEncodeSpacesAndNonASCII() {
        XCTAssertEqual(XtreamClient.percentEncodedPathSegment("a b"), "a%20b")
        let encoded = XtreamClient.percentEncodedPathSegment("şifre")
        XCTAssertFalse(encoded.contains("ş"), encoded)
        XCTAssertTrue(encoded.hasPrefix("%"), encoded)
    }

    /// Kodlama gerektirmeyen karakterler olduğu gibi kalır; aksi hâlde her
    /// adres okunamaz hâle gelirdi.
    func testPathSegmentsLeaveUnreservedCharactersAlone() {
        XCTAssertEqual(XtreamClient.percentEncodedPathSegment("user-1_A.b~c"), "user-1_A.b~c")
        XCTAssertEqual(XtreamClient.percentEncodedPathSegment("12345"), "12345")
    }

    /// Kodlanan parça her zaman geçerli kodlanmış metin olmalı: `%` dışında
    /// ham kalan karakter bulunmamalı ve tek başına `%` ile bitmemeli.
    ///
    /// Neden bu kadar önemli: `URLComponents.percentEncodedPath` ayarlayıcısı
    /// geçersiz kodlama verildiğinde `fatalError` ile çöker (Apple belgesi).
    /// Yani bozuk bir kodlama, oynatma hatası değil **uygulama çökmesi** demek.
    func testEncodedSegmentsAreAlwaysValidPercentEncoding() {
        for sample in ["mustafa", "p@ss+w:rd", "a/b", "şifre", "a b", "%", "%%", "a%b"] {
            let encoded = XtreamClient.percentEncodedPathSegment(sample)
            var index = encoded.startIndex
            while index < encoded.endIndex {
                if encoded[index] == "%" {
                    let next = encoded.index(after: index)
                    XCTAssertTrue(
                        next < encoded.endIndex,
                        "'%' tek başına kalmamalı: \(encoded)"
                    )
                }
                index = encoded.index(after: index)
            }
            XCTAssertEqual(
                encoded.removingPercentEncoding?.isEmpty, false,
                "kodlanan parça çözülebilmeli: \(encoded)"
            )
        }
    }

    // MARK: - Sunucu yolu öneki

    /// Sağlayıcısını bir alt yol altında sunan kullanıcıda (ters vekil
    /// arkasındaki panellerde yaygın) önek **korunmalı**. Önceki kod
    /// `path = "/player_api.php"` diyerek öneki sessizce atıyordu; istekler
    /// yanlış adrese gidiyor ve kullanıcı boş liste ya da "şifre yanlış"
    /// görüyordu.
    func testPathPrefixIsPreserved() {
        XCTAssertEqual(XtreamClient.percentEncodedPathPrefix("/iptv"), "/iptv")
        XCTAssertEqual(
            XtreamClient.percentEncodedPathPrefix("/a/b"),
            "/a/b",
            "çok katmanlı önek korunmalı"
        )
    }

    /// Önek yoksa (adresin kökü, olağan durum) hiçbir şey eklenmez;
    /// davranış değişmemelidir.
    func testEmptyPathPrefixProducesNothing() {
        XCTAssertEqual(XtreamClient.percentEncodedPathPrefix(""), "")
        XCTAssertEqual(XtreamClient.percentEncodedPathPrefix("/"), "")
    }

    /// Önekteki boşluk ve ASCII dışı karakterler kodlanır; `/` ayırıcı kalır.
    /// Kodlama yapılmazsa adres kurulamaz, çift kodlama yapılırsa `%` bozulur.
    func testPathPrefixEncodesSegmentsButKeepsSlashes() {
        XCTAssertEqual(XtreamClient.percentEncodedPathPrefix("/my iptv"), "/my%20iptv")
        let encoded = XtreamClient.percentEncodedPathPrefix("/a/b c")
        XCTAssertEqual(encoded, "/a/b%20c")
        XCTAssertEqual(encoded.filter { $0 == "/" }.count, 2, encoded)
    }

    /// Kodlanan parça adrese geri konduğunda **aynı** metne çözülmeli.
    /// Gidiş-dönüş bozulursa kimlik sunucuda eşleşmez ve 401 alınır.
    func testEncodedSegmentRoundTripsThroughURL() {
        let password = "p@ss+w:rd"
        var components = URLComponents()
        components.scheme = "http"
        components.host = "example.com"
        components.percentEncodedPath = "/movie/user/"
            + XtreamClient.percentEncodedPathSegment(password)
            + "/12.mp4"
        let url = try? XCTUnwrap(components.url)
        XCTAssertEqual(url?.path, "/movie/user/\(password)/12.mp4")
        XCTAssertEqual(url?.lastPathComponent, "12.mp4")
    }
}
