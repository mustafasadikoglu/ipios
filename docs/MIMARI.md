# IPiOS — iOS IPTV Uygulaması Mimari Planı

**Sürüm:** 1.0
**Tarih:** 21 Eylül 2026
**Hedef platform:** iOS 16.0+ (iPhone + iPad)
**Teknoloji:** Swift 5.9+, SwiftUI, AVKit, async/await — üçüncü taraf bağımlılık yok

> Kurulum ve çalıştırma adımları için [`README.md`](../README.md) dosyasına bakın.

---

## 1. Ürün Özeti

IPiOS, kullanıcının kendi IPTV sağlayıcısına bağlanıp canlı TV, film ve dizi içeriklerini
izleyebildiği bir iOS uygulamasıdır. Uygulama **içerik barındırmaz**; yalnızca kullanıcının
girdiği kaynak (Xtream Codes hesabı veya M3U playlist URL'si) üzerinden yayın oynatır.

Bu ayrım kritiktir: uygulama mağaza kuralları açısından "player" konumundadır, "content
provider" değil. Tüm kaynak bilgileri cihazda kalır, hiçbir sunucuya gönderilmez.

---

## 2. Kapsam

### MVP (v1.0) — bu iskelet kodun hedefi

| # | Özellik | Durum |
|---|---------|-------|
| 1 | Xtream Codes API ile giriş (server + username + password) | İskelet hazır |
| 2 | M3U / M3U8 playlist URL'si ve dosya içe aktarma | İskelet hazır |
| 3 | Canlı TV: kategori listesi, kanal listesi, arama | İskelet hazır |
| 4 | EPG: XMLTV parse, şimdi/gelecek program, program bazlı ilerleme çubuğu | İskelet hazır |
| 5 | VOD: film listesi, kategori, detay ekranı | İskelet hazır |
| 6 | Series: dizi listesi, sezon/bölüm yapısı, bölüm oynatma | İskelet hazır |
| 7 | Favoriler (yerel kalıcı depolama) | İskelet hazır |
| 8 | Son izlenenler (recents) | İskelet hazır |
| 9 | Arama (kanal + film + dizi ortak) | İskelet hazır |
| 10 | Ayarlar: kaynak yönetimi, önbellek temizleme | İskelet hazır |

### v1.1+ (MVP dışı, mimaride yeri ayrıldı)

- Catch-up / Timeshift (Xtream `timeshift` parametresi)
- Canlı yayın kaydı (yerel kayıt; DRM ve mağaza kuralları ayrıca değerlendirilecek)
- Chromecast / AirPlay iyileştirmeleri
- iCloud ile favori senkronizasyonu
- Apple TV (tvOS) hedefi
- Çoklu profil / ebeveyn kilidi (PIN ile kategori gizleme)

---

## 3. Genel Mimari

Katmanlı mimari + **MVVM** + protokol tabanlı servis soyutlaması. Üçüncü parti bağımlılık
yok; her şey Apple'ın kendi çatılarıyla (SwiftUI, AVKit, Combine/async-await) yazılıyor.
Bu, uzun vadede mağaza incelemesi ve güncelleme yönetimi açısından en az sürtünmeli yol.

```
┌──────────────────────────────────────────────────────────┐
│  Presentation (SwiftUI Views)                            │
│  LiveTVView · MoviesView · SeriesView · PlayerView · ... │
└───────────────────────┬──────────────────────────────────┘
                        │ @Published state / async çağrılar
┌───────────────────────▼──────────────────────────────────┐
│  ViewModels (@MainActor, ObservableObject)               │
│  LiveTVViewModel · MoviesViewModel · PlayerViewModel ... │
└───────────────────────┬──────────────────────────────────┘
                        │ protokol arayüzleri
┌───────────────────────▼──────────────────────────────────┐
│  Domain (modeller + servis protokolleri)                 │
│  Channel · Movie · Series · EPGProgram · PlaylistSource  │
│  PlaylistProviding · EPGProviding · PlaybackProviding    │
└───────────────────────┬──────────────────────────────────┘
                        │ somut implementasyonlar
┌───────────────────────▼──────────────────────────────────┐
│  Data (servisler + kalıcılık)                            │
│  XtreamClient · M3UParser · XMLTVParser                  │
│  FavoritesStore · RecentsStore · SourceStore · Cache     │
└───────────────────────┬──────────────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────────────┐
│  Core (ağ, hata, yardımcılar)                            │
│  NetworkClient · AppError · Logger · Keychain            │
└──────────────────────────────────────────────────────────┘
```

**Neden protokol tabanlı?** İki farklı kaynak tipi (Xtream ve M3U) aynı ekranları besliyor.
`PlaylistProviding` protokolü sayesinde View katmanı kaynağın Xtream mi M3U mu olduğunu
hiç bilmiyor. Yarın Stalker Portal eklenirse sadece yeni bir implementasyon yazılır, UI
hiç değişmez.

---

## 4. Modül ve Klasör Yapısı

```
ipios/
├── project.yml                       # XcodeGen tanımı (proje üretimi için)
├── README.md                         # kurulum ve çalıştırma notları
├── docs/
│   └── MIMARI.md                     # bu doküman
├── IPiosTests/                       # birim testleri (ayrı test hedefi)
│   ├── M3UParserTests.swift
│   ├── XMLTVDateTests.swift
│   ├── CoreUtilitiesTests.swift
│   ├── PlaybackRoutingTests.swift
│   ├── PlaybackDiagnosticsTests.swift
│   └── LocalizationTests.swift
└── IPiOS/
    ├── App/                          # uygulama girişi ve kök akış
    │   ├── IPiOSApp.swift            # @main giriş noktası
    │   ├── AppEnvironment.swift      # DI konteyneri
    │   ├── RootView.swift            # yasal ekran / onboarding / ana kabuk yönlendirmesi
    │   ├── MainTabView.swift         # TabView iskeleti
    │   └── PlayerPresenter.swift     # oynatıcıyı sunan tam ekran kapak
    ├── Core/                         # altyapı; hiçbir üst katmanı bilmez
    │   ├── AppError.swift            # kullanıcıya gösterilebilir hata modeli
    │   ├── Network/
    │   │   ├── NetworkClient.swift   # async/await HTTP katmanı
    │   │   └── HTTPError.swift
    │   ├── Storage/
    │   │   ├── KeychainStore.swift   # şifreler için güvenli depolama
    │   │   ├── JSONFileStore.swift   # favoriler / recents / kaynaklar
    │   │   └── AppSettings.swift     # yalnızca hassas olmayan ayarlar
    │   ├── UI/
    │   │   ├── Components.swift      # ortak bileşenler (boş/hata/yükleme, rozet…)
    │   │   ├── RemoteImage.swift     # uzak görsel + önbellek
    │   │   └── PreviewGallery.swift  # Xcode Canvas önizlemeleri (#if DEBUG)
    │   └── Utilities/
    │       ├── Theme.swift           # renk, boşluk ve yazı tipi sistemi
    │       ├── Localization.swift    # L.t / L.f yardımcıları
    │       ├── Formatters.swift      # süre, saat aralığı, yüzde…
    │       ├── Logger.swift
    │       └── Debouncer.swift
    ├── Domain/                       # saf iş modelleri ve protokoller
    │   ├── Models/
    │   │   ├── PlaylistSource.swift  # kaynak tanımı (Xtream / M3U)
    │   │   ├── Category.swift
    │   │   ├── Channel.swift
    │   │   ├── Movie.swift
    │   │   ├── Series.swift
    │   │   ├── EPGProgram.swift
    │   │   ├── MediaItem.swift       # ortak arayüz (protokol)
    │   │   └── PlayableItem.swift    # birleşik oynatma modeli (enum)
    │   └── Services/
    │       ├── PlaylistProviding.swift
    │       ├── EPGProviding.swift
    │       └── PlaybackProviding.swift
    ├── Data/                         # protokollerin gerçek uygulamaları
    │   ├── Xtream/
    │   │   ├── XtreamClient.swift
    │   │   └── XtreamDTOs.swift
    │   ├── M3U/
    │   │   ├── M3UParser.swift
    │   │   └── M3UPlaylistProvider.swift
    │   ├── EPG/
    │   │   ├── XMLTVParser.swift
    │   │   └── EPGService.swift
    │   └── Repositories/             # ekranların ortak veri kaynağı
    │       ├── SourcesRepository.swift
    │       ├── FavoritesRepository.swift
    │       ├── RecentsRepository.swift
    │       └── ContentLibrary.swift  # aktif kaynağın içerik aynası
    ├── Player/                       # AVPlayer sarmalayıcıları
    │   ├── AVPlayerEngine.swift
    │   ├── PlaybackDiagnostics.swift # hata sınıflandırma + akış kodek ölçümü
    │   ├── AudioSessionManager.swift
    │   ├── PictureInPictureController.swift
    │   └── VideoSurfaceView.swift
    ├── ViewModels/                   # @MainActor ObservableObject'ler
    │   ├── CatalogViewModel.swift
    │   ├── LiveViewModel.swift
    │   ├── MoviesViewModel.swift
    │   ├── SeriesViewModel.swift
    │   ├── SeriesDetailViewModel.swift
    │   ├── SearchViewModel.swift
    │   ├── FavoritesViewModel.swift
    │   ├── RecentsViewModel.swift
    │   ├── SourcesViewModel.swift
    │   └── PlayerViewModel.swift
    ├── Views/                        # SwiftUI ekranları
    │   ├── Common/                   # satır ve kart bileşenleri
    │   │   ├── ChannelRow.swift
    │   │   ├── MediaRowView.swift
    │   │   └── PosterCard.swift
    │   ├── Legal/LegalView.swift
    │   ├── AddSource/AddSourceView.swift
    │   ├── Live/
    │   │   ├── LiveView.swift
    │   │   ├── ChannelDetailView.swift
    │   │   └── LiveSupportViews.swift
    │   ├── Movies/MoviesView.swift
    │   ├── Series/
    │   │   ├── SeriesView.swift
    │   │   └── SeriesDetailView.swift
    │   ├── Search/SearchView.swift
    │   ├── Player/PlayerView.swift
    │   └── Settings/SettingsView.swift
    └── Resources/
        ├── Assets.xcassets/
        ├── Info.plist
        ├── tr.lproj/
        │   ├── Localizable.strings   # birincil dil
        │   └── InfoPlist.strings     # Info.plist metinleri (ayrı dosya olmak zorunda)
        └── en.lproj/
            ├── Localizable.strings   # ikincil dil
            └── InfoPlist.strings
```

### Katmanlar arası bağımlılık kuralı

Bağımlılık yalnızca aşağı doğru akar: `Views` → `ViewModels` → `Domain` ← `Data`.
`Domain` hiçbir şeyi bilmez; `Core` de `Domain`'i bilmez. Bir ViewModel ekranın
ihtiyacı olan protokolü (`PlaylistProviding` gibi) enjekte edilmiş olarak alır, somut
`XtreamClient`'ı hiç görmez. Böylece Xtream yerine M3U ya da ağ yerine sahte bir
sağlayıcı kullanmak yalnızca `AppEnvironment` içindeki tek satırı değiştirmek olur.


---

## 5. Domain Modeli

### PlaylistSource

Kullanıcının eklediği kaynağı temsil eder. Şifre bu modelde **düz metin tutulmaz**;
Keychain'de saklanır ve model yalnızca bir referans anahtarı taşır.

```swift
struct PlaylistSource: Identifiable, Codable, Hashable {
    enum Kind: Codable, Hashable { case xtream, m3u }
    let id: UUID
    var name: String
    var kind: Kind
    var baseURL: URL           // Xtream: http://host:port  |  M3U: playlist url
    var username: String?      // Xtream
    var credentialKey: String? // Keychain anahtarı (şifre için)
    var epgURL: URL?           // opsiyonel XMLTV kaynağı
    var lastSyncedAt: Date?
}
```

### Kanal / Film / Dizi

Üçü de ortak bir `MediaItem` protokolüne uyar; böylece favoriler, arama ve "son izlenenler"
tek bir koleksiyonda tutulabilir.

```swift
protocol MediaItem: Identifiable, Hashable {
    var id: String { get }
    var title: String { get }
    var imageURL: URL? { get }
    var streamURL: URL { get }
}
```

`Channel`, `Movie` ve `Series` bu protokole uyar. Dizinin `streamURL`'i yoktur — onun yerine
sezon/bölüm ağacı vardır ve `Episode` alt modeli `MediaItem` olur.

### EPGProgram

```swift
struct EPGProgram: Identifiable, Hashable, Codable {
    let id: String
    let channelID: String
    let title: String
    let description: String?
    let start: Date
    let end: Date

    var isLive: Bool { Date() >= start && Date() < end }
    var progress: Double { /* geçen süre oranı 0...1 */ }
}
```

---

## 6. Servis Katmanı

### PlaylistProviding

İki kaynak tipini tek arayüzde birleştirir:

```swift
protocol PlaylistProviding {
    func categories(for kind: CategoryKind) async throws -> [Category]
    func channels(categoryID: String?) async throws -> [Channel]
    func movies(categoryID: String?) async throws -> [Movie]
    func series(categoryID: String?) async throws -> [Series]
    func seriesInfo(seriesID: String) async throws -> SeriesDetail
}
```

| Implementasyon | Kullandığı endpoint'ler |
|---|---|
| `XtreamClient` | `player_api.php?action=get_live_categories` / `get_live_streams` / `get_vod_categories` / `get_vod_streams` / `get_series` / `get_series_info` / `get_short_epg` |
| `M3UPlaylistProvider` | Playlist indirme + `#EXTINF` parse (grup başlığı = kategori) |

### EPGProviding

XMLTV (`tvguide.xml` / `epg.xml`) formatını parse eder. Xtream sağlayıcılarında EPG çoğu
zaman `xmltv.php?username=..&password=..` endpoint'inden gelir; M3U kaynaklarında kullanıcı
ayrı bir EPG URL'si girer.

Performans notu: XMLTV dosyaları 50–200 MB olabilir. Bu yüzden parse işlemi
`XMLParser` (SAX, streaming) ile yapılır, tüm dosya DOM'a alınmaz. Parse edilen veri
channel bazında parçalara bölünüp diske yazılır, bellek şişmez.

### PlaybackProviding

```swift
protocol PlaybackProviding {
    func play(_ item: MediaItem) async throws
    func pause()
    func stop()
    var stateStream: AsyncStream<PlaybackState> { get }
}
```

Somut implementasyon `AVPlayerEngine`. Canlı HLS akışlarında `.m3u8` uzantısı gerekmez;
Xtream'in `stream_type` alanı `m3u8` veya `ts` olabilir — ikisi de AVPlayer tarafından
doğrudan oynatılır.

---

## 7. Ağ Katmanı

`NetworkClient`, `URLSession` üzerine async/await sarmalayıcıdır:

- Otomatik yeniden deneme (exponential backoff, 3 deneme)
- Zaman aşımı: istek 15 sn, kaynak indirme 30 sn
- `URLCache` ile playlist/EPG önbelleği (varsayılan 50 MB)
- Kullanıcı arayüzüne Türkçe hata mesajları döndüren `AppError` haritalaması

Tüm istekler `URLSessionConfiguration.default` ile yapılır; `waitsForConnectivity` açık
bırakılır, böylece hücresel ağa geçişte istekler düşmez.

**ATS (App Transport Security):** Birçok IPTV sağlayıcısı HTTP üzerinden yayın yapar.
Bu nedenle `Info.plist` içinde `NSAppTransportSecurity → NSAllowsArbitraryLoads = true`
gereklidir. Bu bir mağaza incelemesi riskidir; alternatif olarak kullanıcıya uyarı gösterip
yalnızca HTTPS zorunlu tutmak değerlendirilebilir (bkz. Bölüm 11).

**Arka planda ses (`UIBackgroundModes = [audio]`):** Uygulama sesi arka planda çalmaya
devam eder; ekran kilitlendiğinde ya da kullanıcı başka bir uygulamaya geçtiğinde yayın
kesilmez. Bu davranış `AVAudioSession` kategorisinin `.playback` olarak ayarlanmasıyla
birlikte çalışır (bkz. Bölüm 9). Mağaza incelemesinde bu anahtar yalnızca gerçekten
arka planda ses çalındığı için savunulabilir; çalmayan bir uygulamada bulunması reddedilme
nedenidir.

**`UIRequiredDeviceCapabilities = [arm64]`:** Hedef iOS 16'dır ve 64 bit işlemci şarttır.
Adlandırılmış `armv7` anahtarı 32 bit cihazları işaret eder ve App Store yüklemesinde
reddedilir; bu yüzden `arm64` kullanılır.

**`UILaunchScreen`:** Boş bir `<dict/>` verilir. Tek başına bu, sistemin varsayılan
(uygulama arka plan renginde) açılış ekranını üretmesi için yeterlidir. `UIColorName`
anahtarı ancak `Assets.xcassets` içinde bir renk kümesi tanımlıysa doldurulmalıdır; boş
dize ile bırakmak çalışma zamanında uyarı üretir.

---

## 8. Kalıcı Depolama

| Veri | Yer | Neden |
|---|---|---|
| Kaynak listesi, favoriler, son izlenenler, izleme konumları | `Application Support/` altında JSON dosyaları | Basit, şeffaf, migration'ı kolay |
| Xtream şifresi | Keychain (`kSecClassGenericPassword`) | Düz metin saklanmaz |
| Hassas olmayan tercihler (yasal onayı, otomatik oynatma, yatayda tam ekran) | `UserDefaults` (`AppSettings`) | Küçük, anahtar-değer; yedeklenmesi sorun değil |
| Görsel önbelleği (poster/logo) | `URLCache` + `NSCache` | Ağ trafiğini azaltır |
| EPG | Kanal bazlı parçalanmış JSON | Büyük XMLTV dosyalarını tekrar parse etmemek için |

`UserDefaults` ile Keychain ayrımı bilinçlidir: `AppSettings` yalnızca sızması hâlinde
kullanıcıya zarar vermeyecek veriyi tutar ve sınıfın başında bunu belgeleyen bir not
bulunur. Şifre içeren hiçbir şey `UserDefaults`'a, JSON dosyasına veya log'a yazılmaz;
`PlaylistSource` modeli düz metin şifre alanı **taşımaz**, yalnızca Keychain'deki kaydın
anahtarını (`credentialKey`) tutar.

SwiftData veya Core Data **kullanılmadı**. Nedeni: veri hacmi 100k+ kanal olabilir ama
sorgu ihtiyacı basit (kategoriye göre filtre, isimde ara). Dosya tabanlı yaklaşım bu ölçekte
daha hızlı ve daha az kırılgan. Veri 200k kanalı aşarsa SQLite'a geçiş değerlendirilecek —
`SourcesRepository` arayüzü bunu gizlediği için UI etkilenmez.

---

## 9. Ekran Akışı

```
İlk açılış
   └─> Kaynak Yok  ──> AddSourceView ──> [Xtream formu | M3U formu]
                                            │
                                    Bağlantı testi + sync
                                            │
                                    ┌───────▼────────┐
                                    │   RootView     │
                                    │   TabView      │
                                    └───────┬────────┘
        ┌────────────┬──────────────┬───────┴─────┬────────────┐
        ▼            ▼              ▼             ▼            ▼
    Canlı TV      Filmler        Diziler      Arama       Ayarlar
        │            │              │
        │            │              └─> SeriesDetailView (sezon/bölüm)
        │            └─> MovieDetailView
        │                    │
        └────────────────────┴──> PlayerView (AVPlayer, tam ekran)
```

Her liste ekranında ortak davranış: kategori çubuğu (yatay chip'ler), arama alanı,
favori yıldızı, EPG ilerleme çubuğu (yalnızca canlı TV'de).

---

## 10. Oynatıcı Tasarımı

`AVPlayerViewController`, SwiftUI içinde `UIViewControllerRepresentable` ile sarılır.
Kritik noktalar:

- **Canlı akış:** `.m3u8` HLS akışlarında `player.currentItem.duration` sonsuzdur;
  ilerleme çubuğu gösterilmez, "CANLI" etiketi ve kanal adı gösterilir.
- **VOD/Dizi:** ilerleme çubuğu, 10 sn ileri/geri, altyazı ve ses parçası seçimi.
- **Arka plan:** `AVAudioSession` kategorisi `.playback`; ekran kilidi ve arka plan sesi
  desteklenir. `AVPlayer` `pipController` ile Picture-in-Picture.
- **İzleme konumu:** VOD ve dizilerde `currentTime` periyodik olarak diske yazılır;
  "Devam et" özelliği buradan beslenir.
- **Hata yönetimi:** akış açılmazsa kullanıcıya "Kanal şu an yayında değil" mesajı ve
  yeniden dene butonu.

---

## 11. Riskler ve Kararlar

| Risk | Etki | Alınan karar |
|---|---|---|
| ATS `NSAllowsArbitraryLoads` mağaza incelemesinde soru işareti | Yüksek | v1'de HTTP'ye izin verilecek; mağazaya yüklemeden önce yalnızca HTTPS + kullanıcı onayı senaryosu değerlendirilecek. Kaynak URL şeması ağ katmanında tek yerden kontrol edilir. |
| Uygulamanın "korsan yayın aracı" olarak algılanması | Yüksek | Uygulama içerik barındırmaz, sağlayıcı sağlamaz. İlk açılışta ve kaynak ekleme ekranında yasal sorumluluğun kullanıcıda olduğunu belirten onay metni gösterilir. Mağaza açıklamasında "player only" vurgusu yapılır. |
| Telif hakkı bildirimleri (DMCA) | Orta | Uygulama hiçbir katalog/indeks sunmadığı için yüzey alanı minimaldir. |
| 100k+ kanallı playlistlerde liste performansı | Orta | `LazyVStack` + sayfalama; arama için arka planda indeksleme. |
| XMLTV dosyalarının büyüklüğü | Orta | Streaming `XMLParser`, kanal bazlı parçalı önbellek. |
| Kullanıcı şifrelerinin sızması | Yüksek | Keychain, cihaz dışına çıkmaz, loglarda maskelenir. |
| Sağlayıcı API tutarsızlıkları | Orta | Xtream DTO'ları tüm alanları `optional` kabul eder, eksik alanlarda güvenli varsayılan. |
| Kimlik bilgilerinin akış adresinde yol içinde taşınması | Yüksek | Şifre URL yolunun bir parçasıdır ve yüzde kodlanmalıdır. `URLComponents.path` ayarlayıcısı alt sınırlayıcıları (`@`, `+`, `:`, `/`) kodlamaz; bu yüzden kodlama `percentEncodedPathSegment` ile açıkça yapılır. Ayrıca `percentEncodedPath` ayarlayıcısı geçersiz kodlamada `fatalError` verir; bu yüzden kodlama asla ham parçaya geri düşmez. |
| Sunucu adresinde yol öneki | Orta | Xtream uç noktaları adresin köküne sabitlenmez; kullanıcının verdiği yol öneki (`http://host/iptv`) korunur. Öneki atmak, sağlayıcısını alt yol altında sunan panellerde isteği yanlış adrese gönderir. |
| Sessiz biçim/konteyner uyumsuzluğu ("başka uygulamada açılıyor, bunda açılmıyor") | Yüksek | Neden tahmin edilmez, **ölçülür**: akışın taşıdığı kodekler `AVAsset` ile okunur (`PlaybackDiagnostics`). Desteklenmeyen bir ses kodeği görüntü kodeği destekli olsa bile öğenin tamamını düşürür; kullanıcıya kodeğin adı söylenir ve sağlayıcıya iletilebilecek dilden bağımsız bir teşhis satırı eklenir. |

---

## 12. Yol Haritası

| Faz | İçerik | Süre tahmini |
|---|---|---|
| 1 | İskelet + kaynak ekleme + M3U parse + oynatıcı | 1 hafta |
| 2 | Xtream entegrasyonu + canlı TV + kategoriler + arama | 1 hafta |
| 3 | EPG parse + şimdi/gelecek + ilerleme çubuğu | 1 hafta |
| 4 | VOD + Series + izleme konumu + favoriler | 1 hafta |
| 5 | Cila: tasarım, hata durumları, erişilebilirlik, testler | 1 hafta |
| 6 | Mağaza hazırlığı: ekran görüntüleri, gizlilik politikası, inceleme notları | 3 gün |

---

## 13. Test Stratejisi

Testler ayrı bir `IPiosTests` hedefinde toplanmıştır (`project.yml` içinde
`type: bundle.unit-test`, ana uygulamaya bağımlı). Ağ erişimi gerektirmezler;
tamamı saf fonksiyonları ve dosya tabanlı mantığı sınar.

| Dosya | Kapsam |
|---|---|
| `M3UParserTests` | Bozuk/eksik satırlar, tırnaksız değer, BOM, CRLF, çoklu adres, `#EXTGRP`/`group-title` önceliği |
| `XMLTVDateTests` | `yyyyMMddHHmmss +ZZZZ` biçiminin çözümlenmesi, saat dilimi kaydırması, geçersiz damga |
| `CoreUtilitiesTests` | `FlexibleInt`/`FlexibleString`/`FlexibleDouble` toleransı, `AppError` eşlemesi, `HTTPError` sınıflandırması |
| `LocalizationTests` | İki dil arasında anahtar eşliği, yinelenen anahtar, yer tutucu uyumu, boş değer, tanımsız anahtar |

`CoreUtilitiesTests`'in ağırlığı `Flexible*` sarmalayıcılarındadır: Xtream panelleri
aynı alanı bazen sayı, bazen metin döndürür (`"42"` ve `42`). Tolerans kaybedilirse
tek bir kayıt yüzünden **tüm kanal listesi** boş gelir; testler bunu engeller.

`LocalizationTests` bir *koruma* testidir: yeni bir metin eklerken yalnızca tek dile
yazmak ya da `%d` yerine `%@` kullanmak derleme hatası vermez, uygulama çalışarken
bozuk görünür. Test bunu derleme aşamasında yakalar.

Planlanan ama henüz yazılmamış: `NetworkClient` için mock'lanmış yanıtlarla
entegrasyon testleri (401/404/timeout), UI testleri (kaynak ekleme akışı,
kategori-arama gezinmesi) ve gerçek sağlayıcılarla manuel testler.

---

## 14. Yerelleştirme

Birincil dil Türkçe, ikincil İngilizce. Kullanıcıya görünen hiçbir metin koda
gömülü değildir; hepsi `L.t("anahtar")` / `L.f("anahtar", argümanlar)` üzerinden
`Localizable.strings` dosyasından gelir. Çözümleme `Localization.swift` içindedir
ve `NSLocalizedString` sarmalar.

Bunun **tek istisnası** `Info.plist` metinleridir. Sistem, bu metinleri (örneğin
yerel ağ izni istemini) uygulama daha başlamadan okur ve yalnızca
`InfoPlist.strings` dosyasına bakar — `Localizable.strings` burada işe yaramaz.
Bu yüzden aynı metin her iki `.lproj` klasöründe `InfoPlist.strings` içinde ayrıca
tutulur. Şu an tek giriş `NSLocalNetworkUsageDescription`'dır.

`%d` / `%@` yer tutucuları iki dilde **birebir aynı** olmak zorundadır; `Format`
yardımcıları metni `String(format:)` ile üretir ve uyuşmazlık çalışma anında
çökmeye yol açar. `LocalizationTests` bunu denetler. Türkçede sayıdan sonra çoğul
eki gelmediği için (`2 kanal`, `42 kanal`) `.stringsdict` dosyasına gerek yoktur.

