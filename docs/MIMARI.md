# IPiOS — iOS IPTV Uygulaması Mimari Planı

**Sürüm:** 1.0
**Tarih:** 21 Eylül 2026
**Hedef platform:** iOS 16.0+ (iPhone + iPad)
**Teknoloji:** Swift 5.9+, SwiftUI, async/await + oynatma çekirdeği olarak VLCKit (libvlc)

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

Katmanlı mimari + **MVVM** + protokol tabanlı servis soyutlaması. Uygulama katmanları
SwiftUI, Foundation ve Combine ile yazılıyor; **tek üçüncü taraf bağımlılık** oynatma
çekirdeğidir (VLCKit/libvlc). Bu sınır bilinçli: sağlayıcı VOD'u yalnızca Matroska olarak
sunduğu için (bkz. Bölüm 11) `AVFoundation` yeterli değildir, buna karşılık veri, ağ,
arayüz ve depolama katmanlarında bağımlılık eklemeye gerek yoktur.

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
│   ├── PlaybackTrackTests.swift
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
    │   │   ├── PlaybackTrack.swift   # ses/altyazı izi + seçim kümesi
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
    ├── Player/                       # libvlc (VLCKit) oynatma çekirdeği
    │   ├── VLCPlayerEngine.swift     # PlaybackProviding'in libvlc uygulaması
    │   ├── VLCLogger.swift           # libvlc günlüğünü yakalar (teşhis kaynağı)
    │   ├── VLCDiagnostics.swift      # günlükten hata sınıflandırma + akış ölçümü
    │   ├── PlaybackDiagnostics.swift # hata metinleri + kodek adları sözlüğü
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
    │   ├── Player/
    │   │   ├── PlayerView.swift    # tam ekran oynatıcı + kontrol katmanı
    │   │   └── TrackMenuView.swift  # ses/altyazı seçim kartı
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
@MainActor
protocol PlaybackProviding: AnyObject {
    var state: PlaybackState { get }
    var currentTitle: String? { get }
    var isLive: Bool { get }
    var duration: Double? { get }
    var currentTime: Double { get }
    var didResumeFromSavedPosition: Bool { get }
    func load(_ item: any MediaItem, startAt: Double?) async
    func play(); func pause(); func togglePlayPause(); func stop()
    func seek(by seconds: Double); func seek(to seconds: Double)
    func persistPosition() async
    func setVolume(_ value: Float)

    // İzler (gömülü ses / altyazı)
    var tracks: PlaybackTrackSet { get }
    func selectAudioTrack(id: String)
    func selectSubtitleTrack(id: String)
    func disableSubtitles()
}
```

Somut implementasyon `VLCPlayerEngine` (libvlc). Arayüz ayrı tutulması işe yaradı:
oynatma motoru bir kez, ekranlara hiç dokunulmadan değiştirildi.

Xtream'in `stream_type` alanı `m3u8` veya `ts` olabilir; **ikisi de libvlc tarafından
doğrudan oynatılır**, dolayısıyla canlı yayında taşıyıcı seçimi bir kısıt değildir.

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
        └────────────────────┴──> PlayerView (libvlc, tam ekran)
```

Her liste ekranında ortak davranış: kategori çubuğu (yatay chip'ler), arama alanı,
favori yıldızı, EPG ilerleme çubuğu (yalnızca canlı TV'de).

---

## 10. Oynatıcı Tasarımı

Oynatma çekirdeği **libvlc**'dir (VLCKit paketi). `PlayerView` kendi kontrol arayüzünü
çizer; sistem oynatıcısı kullanılmaz. Görüntü yüzeyi `UIViewRepresentable` ile sarılan
sade bir `UIView`'dır ve `VLCMediaPlayer.drawable` üzerine bağlanır.

Kritik noktalar:

- **Görüntü yüzeyi:** `drawable` **herhangi bir `UIView`** kabul eder; libvlc kendi görüntü
  alt katmanını o görünüme ekler. Katman tipi sabitlenmez, `AVPlayerLayer` gerekmez.
  Bağ **iki yönlüdür** (`willMove(toWindow:)`): `drawable` güçlü tutulduğu için bırakılmazsa
  kapanan ekranın görünümü bellekte asılı kalır.
- **Ölçekleme:** tek kip kullanılır (`VLCVideoFitSmaller` ≈ oranı koruyarak sığdırma).
  Kırpan kip **bilinçli olarak kullanılmaz**: yayının kenarları (kanal logoları, alt
  bantlar) kesilir ve kullanıcı bunu "görüntü sığmıyor" olarak bildirmişti.
- **Canlı akış:** süre bilinmez (`VLCTime.nullTime`), ilerleme çubuğu gösterilmez;
  "CANLI" etiketi gösterilir. Arama yapılmaz (`isSeekable` yanlış).
- **VOD/Dizi:** ilerleme çubuğu ve 10 sn ileri/geri. Konum `player.time` üzerinden
  okunur; `VLCTime.intValue` **milisaniye** döner, arayüz saniye ile çalışır.
- **Ses:** `AVAudioSession` kategorisi `.playback` (arka plan sesi için); ses seviyesi
  `VLCAudio.volume` ile ayarlanır ve bu **tamsayı bir ölçektir** — arayüzün 0...1 aralığı
  dönüştürülmeden verilirse ses kapanır.
- **İzleme konumu:** VOD ve dizilerde konum periyodik olarak diske yazılır; "Devam et"
  özelliği buradan beslenir. Kaydedilmiş konum oynatma **başladıktan sonra** uygulanır:
  libvlc arama isteğini ancak akış çözüldükten sonra işleyebilir.
- **Teşhis:** `VLCLogger` libvlc'nin günlüğünü yakalar, `VLCDiagnostics` bu günlükten
  nedeni **okur** (bkz. Bölüm 11). Hata metni tahminle değil kanıtla üretilir.
- **Picture-in-Picture:** `AVPlayer` döneminde `AVPictureInPictureController` somut bir
  `AVPlayerLayer` üzerine kuruluyordu; bu yol libvlc ile kullanılamaz. VLCKit 4.0 kendi PiP
  API'sini sunar (`VLCPictureInPictureDrawable`, `...MediaControlling`,
  `...WindowControlling`) ancak bu protokollerin Swift köprüsü derleyici olmadan
  doğrulanamadığı için **şimdilik uygulanmadı**; arayüz düğmeyi çizmez
  (bkz. `PictureInPictureController`).

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
| Sessiz biçim/konteyner uyumsuzluğu ("başka uygulamada açılıyor, bunda açılmıyor") | Yüksek | **Ölçülerek çözüldü.** Neden ölçüldü ve tek bir kök neden bulundu: sağlayıcı VOD'u yalnızca **Matroska (`.mkv`)** olarak sunuyor; `AVFoundation`'ın Matroska demuxer'ı yoktur. Uzantı değiştirmek kurtarmaz — sunucu `.mp4`/`.m3u8`/`.avi`/`.ts` adreslerinde HTTP 200 ile **0 bayt** gövde döndürüyor, yalnızca `.mkv` gerçek veri veriyor (ölçüm: `scripts/xtream_teshis.py`). Eksik olan şey yedek bir adres değil, bir **demuxer**'dı; bu yüzden oynatma çekirdeği libvlc'ye taşındı. Ayrıntı için Bölüm 11.1. |
| VLCKit bağımlılığının kapsamı genişletmesi | Orta | Bağımlılık **yalnızca oynatma katmanına** alındı. Veri, ağ, arayüz ve depolama katmanları Apple çatılarıyla yazılmaya devam ediyor; bu sınır `scripts/static_check.py` ile denetlenir (oynatma yolu `AVFoundation`'a dönerse CI kırılır). |
| VideoLAN etiketlerinin tutarsızlığı | Orta | `exactVersion` **zorunlu**: `4.0.0a21` geçersiz semver iken `4.0.0-a24` geçerlidir. Sürüm aralığı verilirse SwiftPM geçerli en yüksek etiketi kendi seçer ve beklenmedik bir derlemeye düşer. Sabitleme hem `project.yml` içinde hem statik denetimde tutulur. |
| Kodek tablosunun artık hüküm vermemesi | Orta | libvlc AC3/E-AC3/DTS/TrueHD/Opus ve AV1/VP9'u yazılım çözücüleriyle oynatır. `AVPlayer` döneminden kalan "bu kodek tabloda varsa çalınamaz" varsayımı **yanlış teşhis** üretirdi (kullanıcı boşuna sağlayıcıdan AAC isterdi). Tablo artık yalnızca **adlandırma** sözlüğüdür; hüküm yalnızca libvlc'nin günlükte şikâyet ettiği durumda verilir. `PlaybackDiagnosticsTests` bunu teste bağlar. |
| Görüntü yüzeyi oynatma başlamadan bağlanmazsa "ses var, görüntü yok" | Yüksek | Yüzey artık `VideoSurfaceView` içinde üretilmez; **motorun malıdır** (`VLCPlayerEngine.videoSurface`) ve oynatıcı kurulurken bir kez `drawable` olarak atanır, hiç koparılmaz. Ayrıntı ve ölçülmüş belirti için Bölüm 11.2. |
| İleri sarma sırasında gösterge çıkmaması ("donuyor, yüklenmiyor") | Yüksek | Sarma durumu motorda açıkça izlenir (`isSeeking`) ve gösterge sarma boyunca açık kalır; kapatma kararı "zaman ilerledi" değil "hedefe ulaşıldı" ölçütüne ve `.playing` için asgari bir bekleme süresine bağlanır. Ayrıca sağlayıcının HTTP `Range` desteği ölçülür (`xtream_teshis.py` bölüm `[5d]`). Ayrıntı için Bölüm 11.3. |
| VLCKit iz nesnelerinin her okumada yeniden üretilmesi | Yüksek | `VLCMediaPlayer.audioTracks`/`textTracks` her okumada **yeni nesneler** döndürür (`_tracksForType:`), bu yüzden o nesneler doğrudan SwiftUI listesine konamaz — kimlik her yenilemede değişir ve seçim kayar. Arayüze yalnızca kararlı alanlar taşınır (`PlaybackTrack.trackId`) ve seçim kimlikle yapılır. Ayrıntı Bölüm 11.4. |
| `mediaPlayerTrackSelected` delege geri çağrısının çökme riski | Yüksek | Başlıkta `nonnull` bildirilen iki parametre uygulamada **nil geçilebiliyor** (`unselected ? … : nil`); Swift bunları opsiyonel olmayan `String` olarak alır ve nil geldiğinde köprüleme çöker. nil tam da *hiçbir iz seçili değilken* bir iz seçilince geçilir. Geri çağrı bu yüzden **uygulanmaz**; liste seçim yapan yollarda ve iz ekleme/güncelleme bildirimlerinde tazelenir. Ayrıntı Bölüm 11.4. |
| Sağlayıcının HTTP `Range` desteklememesi | Orta | Sarma dosyanın başından indirmeyi gerektirir ve uzun sürer; bu sağlayıcının sınırıdır, uygulamanın kusuru değil. Teşhis betiği bunu **hüküm** olarak raporlar ki kullanıcı boşuna uygulamada çözüm aramasın. |

### 11.1 Ölçülmüş kök neden: neden filmler oynamıyordu

Kullanıcının bildirimi: *"farklı bir uygulamada filmler çalışıyor ama bu uygulamada
açılmıyor; sadece isimleri ve posterleri geliyor, video oynamıyor."* Üç tur boyunca
ekranda yalnızca "Oynatma başlatılamadı." göründü ve sorun teşhis edilemedi. Neden
bulunamıyordu: **kanıt sanılan şey kanıt değildi.** Hata metni, iz listesi ve `AVError`
kodu — hepsi dolaylıydı.

Bu yüzden neden tahmin edilmedi, **ölçüldü**. `scripts/xtream_teshis.py` gerçek
sağlayıcıya karşı çalıştırıldı ve aynı filmin adresi farklı uzantılarla denendi:

| Denenen | Sonuç |
|---|---|
| `.mkv` (sağlayıcının bildirdiği uzantı) | HTTP 200, **9186–9196 bayt gerçek veri** |
| `.mp4` | HTTP 200, **0 bayt** |
| `.m3u8` | HTTP 200, **0 bayt** |
| `.avi` | HTTP 200, **0 bayt** |
| `.ts` | HTTP 200, **0 bayt** |
| Canlı yayın, `.m3u8` | HTTP 200 `[HLS]`, 2782 bayt — **çalışıyor** |

Sağlayıcı her film ve bölüm için `container_extension` alanını `mkv` olarak bildiriyor.
Yani sunucu VOD'u gerçekten yalnızca Matroska olarak veriyor; diğer uzantılar 200
dönse bile gövde boştur. **Sonuç:** eksik olan şey yedek bir adres değil, bir
**demuxer**'dır. `AVFoundation` çerçevesinde Matroska demuxer'ı yoktur — bu bir
uygulama kusuru değil, çerçeve sınırıdır. Uzantı değiştirmek de kurtarmaz.

Canlı yayınların aynı sağlayıcıda sorunsuz çalışması bu teşhisi doğrular: HLS
paketlemesi `AVPlayer`'ın çözebildiği tek biçimdi ve tam da o biçim çalışıyordu.

**Alınan karar:** oynatma çekirdeği libvlc'ye (VLCKit) taşındı. Projenin "üçüncü taraf
bağımlılık yok" ilkesi bu tek katman için bilinçli olarak esnetildi; Matroska'yı
çözmenin Apple çatılarıyla bir yolu yoktur.

**İkincil kazanç:** `AVPlayer` döneminde hata nedeni dolaylı kanıttan kestiriliyordu.
libvlc başarısızlığın nedenini kendi günlüğünde açıkça yazar (tanınmayan demuxer,
çözülemeyen kodek, HTTP durum kodu). Teşhis artık **okunuyor**, tahmin edilmiyor —
bu, benzer bir kusurun bir daha üç tur sürmemesini sağlar.

### 11.2 Ölçülmüş kök neden: neden "ses var, görüntü yok"

libvlc'ye geçiş filmleri oynattı ama yeni bir belirti çıktı: *"videolar açıldı fakat
ses var görüntü yok; bazıları açılıyor, bazıları öyle."* Belirtinin **kararsız**
olması en değerli ipucuydu: kararsız belirti, kararsız bir **zamanlama** demektir.

Kök neden bir yarıştı. Görüntü yüzeyi `VideoSurfaceView.makeUIView` içinde üretiliyor,
`player.drawable`'a bağlanıyor, görünüm ekrandan çıktığında
(`willMove(toWindow: nil)`) ise bağ `player.drawable = nil` ile **koparılıyordu**.
Oysa oynatma `PlayerPresenter.present()` içinde, kapak görünümü daha çizilmeden
başlatılır. Yani libvlc görüntü çıkışını kurarken `drawable` çoğu zaman **henüz
atanmamış** oluyordu. Ses çıkışı kurulur, görüntü çıkışı kurulamaz.

Kararsızlığın açıklaması da buydu: ağ yavaş açılan dosyalarda yüzey yetişiyordu,
hızlı açılanlarda yetişmiyordu. Aynı yarış kapak kapanıp açıldığında ve döndürme
sırasında da tekrarlanıyordu.

**Alınan karar:** yüzeyin sahibi görünüm değil **motordur**. `VLCPlayerEngine.videoSurface`
oynatıcıyla aynı ömre sahiptir; `configurePlayer()` içinde bir kez `drawable` olarak
atanır ve hiçbir koşulda koparılmaz. `VideoSurfaceView` artık yüzey **üretmez**,
yalnızca barındırır (`SurfaceHostView`). Bağ oynatma başlamadan çok önce kurulduğu
için yarış tümüyle ortadan kalkar. `drawable` kuvvetli tutulduğundan yüzey motordan
uzun yaşayamaz; motor uygulama ömrü boyunca tek olduğu için bu bir sızıntı değildir.

### 11.3 Ölçülmüş belirti: ileri sarınca donma

Aynı bildirimin ikinci yarısı: *"ileri bir noktaya sardığımda görüntü donuyor,
yüklenmiyor."* Kullanıcıya sorulduğunda sesin de durduğu, yani oynatmanın tamamen
duraksadığı doğrulandı — bir arayüz kilitlenmesi değil.

İki ayrı sorun üst üste biniyordu:

**Birincisi, gösterge hiç çıkmıyordu.** Tampon göstergesinin koşulu
`!hasStartedPlaying || !state.isPlaying` idi. Oynatma bir kez başladıktan sonra bu
koşul **hiçbir zaman** doğru olamaz; yani sarma sırasında — ekranda donmuş bir kare
varken ve yeni konum indirilirken — kullanıcı hiçbir geri bildirim görmüyordu.
Yükleme sürüyordu, yalnızca görünmüyordu.

Düzeltme, sarma durumunu motorda açıkça izlemektir (`isSeeking`) ve göstergenin
görünürlüğünü tek bir yerden (`updateBufferingIndicator`) belirlemektir. Kritik
ayrıntı **kapatma ölçütüdür**: "zaman ilerledi" demek yanlıştır, çünkü libvlc arama
isteğini işleyene kadar eski konumdan bildirim göndermeye devam eder ve gösterge
hemen kapanır — kullanıcı yine donmuş kareye bakar. Ölçüt "istenen konuma ulaşıldı"
olmalıdır (anahtar kare hizalaması için birkaç saniyelik toleransla). `.playing`
bildirimi için de koşulsuz kapatma yanlıştır: libvlc bu bildirimi yeni kare çizilmeden
önce gönderebilir. Bu yüzden sarmadan sonra asgari bir bekleme süresi aranır; iki uç
davranış da (erken kapatma / hiç kapatmama) bu süreyle ayrılır.

**İkincisi, sarma gerçekten yavaş olabilir.** Bunun nedeni uygulamada değil
sağlayıcıda olabilir: sunucu HTTP `Range` isteklerini yok sayıyorsa, sarma dosyanın
**başından** yeniden indirilmesini gerektirir. Bu yüzden teşhis betiğine
`[5d]` bölümü eklendi: `Accept-Ranges` başlığı ve bir `Range` isteğinin gerçekten
206 dönüp dönmediği ölçülür. Sonuç **hüküm** olarak raporlanır — sağlayıcı
desteklemiyorsa bu bir sunucu sınırıdır ve kullanıcı boşuna uygulamada çözüm
aramamalıdır.

---

### 11.4 Ses ve altyazı izi seçimi: kimlik kararlıdır, nesne değil

**İstenen:** oynatıcıda gömülü ses ve altyazı izleri arasında geçiş yapmak.
Kapsam bilinçli olarak **gömülü izlerle** sınırlıdır; dışarıdan `.srt` yüklemek
kapsam dışıdır.

**Birinci ölçüm: iz nesneleri kararlı değil.** VLCKit kaynağına bakıldı
(`Headers/Public/Playback/VLCMediaPlayer.h` ve `Sources/Playback/VLCMediaPlayer.m`,
sürüm `4.0.0-a24`). `audioTracks`, `videoTracks` ve `textTracks` özelliklerinin üçü
de aynı özel metoda gider:

```objc
- (NSArray<VLCMediaPlayerTrack *> *)_tracksForType:(const libvlc_track_type_t)type
{
    libvlc_media_tracklist_t *tracklist = libvlc_media_player_get_tracklist(_playerInstance, type, false);
    ...
    for (size_t i = 0; i < tracklistCount; i++) {
        libvlc_media_track_t *track_t = libvlc_media_tracklist_at(tracklist, i);
        VLCMediaPlayerTrack *track = [[VLCMediaPlayerTrack alloc] initWithMediaTrack: track_t mediaPlayer: self];
        [tracks addObject: track];
    }
```

Yani **her okuma yeni bir dizi ve yeni nesneler üretir.** Bu yüzden `VLCMediaPlayer.
Track` doğrudan `Identifiable` yapılıp SwiftUI listesine konamaz: her yenilemede
kimlik değişir, liste baştan kurulur ve seçim "kayar". Arayüze taşınan şey
`PlaybackTrack` olur ve o yalnızca **kararlı** alanları taşır: libvlc'nin iz kimliği
(`trackId`) ve okunabilir ad. Seçim her zaman kimlikle yapılır, indeksle veya nesne
kimliğiyle değil.

**İkinci ölçüm: ses izi seçiminde `setSelected` güvenilmez.** Aynı kaynakta:

```objc
if (type == libvlc_track_audio && selectedTrackIDs.count >= 2) {
    VKLog(@"WARNING: selecting multiple audio tracks is currently not supported.");
    return;
}
```

`setSelected = true` çağrısı, o türden **iki veya daha fazla iz zaten seçiliyse**
sessizce hiçbir şey yapmaz. Buna karşılık `setSelectedExclusively = true` doğrudan
`libvlc_media_player_select_track` çağırır ve güvenilirdir. Bu yüzden ses seçimi
`isSelectedExclusively` üzerinden yapılır.

**Üçüncü ölçüm: bir delege geri çağrısı çökme riski taşıyor ve bu yüzden
uygulanmadı.** `mediaPlayerTrackSelected:selectedId:unselectedId:` başlıkta
`NS_ASSUME_NONNULL_BEGIN` bloğu içinde bildirilmiştir, yani parametreler `nonnull`:

```objc
- (void)mediaPlayerTrackSelected:(VLCMediaTrackType)trackType
                      selectedId:(NSString *)unselectedId   // başlıktaki ad yanlış
                    unselectedId:(NSString*)unselectedId;
```

Ancak uygulamada iki parametre de **nil olabiliyor**:

```objc
NSString *unselectedId = unselected ? [NSString stringWithUTF8String:unselected] : nil;
```

Swift `nonnull` bir `NSString *` parametresini **opsiyonel olmayan `String`** olarak
içeri alır. nil geçildiğinde köprüleme çöker — ve nil tam da **hiçbir iz seçili
değilken** bir iz seçildiğinde geçilir, yani kullanıcının altyazıyı ilk kez açtığı
anda. Başlıktaki `nonnull` işareti burada bir güvence değil, bir yanlış anlamadır.
Bu geri çağrı bu yüzden **uygulanmaz**; işlevsel kayıp yoktur: seçim yapan üç yolun
üçü de listeyi kendisi tazeler, libvlc'nin kendi kararıyla yaptığı seçim ise
`mediaPlayerTrackAdded` ve `mediaPlayerTrackUpdated` bildirimleriyle yakalanır
(liste o bildirimde zaten yeniden okunur ve `isSelected` libvlc'den taze gelir).

**Dördüncü karar: iç içe `ObservableObject` yayını görünüme geçmez.** `PlayerView`
yalnızca `PlayerViewModel`'i dinler. Motorun `tracks` yayınına doğrudan abone
olunsaydı liste değiştiğinde ekran yenilenmez ve kullanıcı menüyü açtığında **boş**
liste görürdü. Bu yüzden görünüm modeli motorun yayınını kendi `@Published` alanına
kopyalar.

**Beşinci karar: altyazıyı kapatmak geçerli bir seçimdir.** `selectedSubtitleID ==
nil` "hata" değil "Kapalı" demektir ve menüde bu her zaman ilk satırdır. Ayrıca menü
açıkken kontrollerin kendiliğinden gizlenmesi durdurulur; aksi hâlde menü kontrol
katmanıyla birlikte kaybolur ve seçim yarıda kesilirdi.

**Altıncı ölçüm: Swift köprüleme etiketi kısaltır.** İlk derleme şu hatayla
düştü:

```
error: 'mediaPlayerTrackAdded(_:withType:)' has been renamed to 'mediaPlayerTrackAdded(_:with:)'
```

Objective-C bildirimi `mediaPlayerTrackAdded:withType:` şeklindedir, ancak Swift
köprülemesi argüman tipinin adıyla (`VLCMedia.TrackType`) aynı olan son sözcüğü
(`Type`) düşürüp etiketi `with`e indirir. Üç iz bildiriminin üçü de aynı tuzağa
sahiptir. Bu tür bir hata **yalnızca Swift derleyicisi olan ortamda** görülür —
yani bu depoda yalnızca CI'da. Bu yüzden `scripts/static_check.py` içine bir
denetim eklendi (bkz. 13. Bölüm): `withType` etiketi yazılırsa statik denetim
kırılır ve hata CI'ın ilk işinde, derlemeden önce yakalanır.

**Kapsam sınırı:** yalnızca **gömülü** izler. Dışarıdan altyazı dosyası yüklemek
(`VLCMediaSlave` yolu) bu sürümün dışındadır.

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
| `PlaybackDiagnosticsTests` | Hata sınıflandırmasının **sırası**, kodeğin tek başına hüküm vermemesi, kanıt cümlesi eşleşmesi, kesilme ayrımı |
| `PlaybackRoutingTests` | Aday adres listesinin içeriği ve sırası, uzantı değiştirmede kimlik bilgisinin korunması, sorgu parametrelerinin taşınması |
| `PlaybackTrackTests` | İz seçiminde **kimlik** temelli eşleşme, menü görünürlük ölçütü, altyazının "kapalı" olmasının geçerli bir durum olması, boş ad → 1 tabanlı numaralı etiket |

`CoreUtilitiesTests`'in ağırlığı `Flexible*` sarmalayıcılarındadır: Xtream panelleri
aynı alanı bazen sayı, bazen metin döndürür (`"42"` ve `42`). Tolerans kaybedilirse
tek bir kayıt yüzünden **tüm kanal listesi** boş gelir; testler bunu engeller.

`LocalizationTests` bir *koruma* testidir: yeni bir metin eklerken yalnızca tek dile
yazmak ya da `%d` yerine `%@` kullanmak derleme hatası vermez, uygulama çalışarken
bozuk görünür. Test bunu derleme aşamasında yakalar.

`PlaybackDiagnosticsTests` ve `PlaybackRoutingTests` de aynı türden koruma
testleridir; ikisi de VLCKit geçişinde yazıldı ve **ürün kusurunun geri gelmesini**
engeller. İlki sınıflandırmanın sırasını sabitler (sunucu reddi kodek hükmünden önce
gelir; ölçülen kodek tek başına "çalınamaz" demek değildir), ikincisi aday adres
listesinin içeriğini ve sırasını. Bu kurallar sessizce geri alınırsa derleme
bozulmaz — yalnızca filmler yeniden oynamaz ve kusur üç tur boyunca görünmez kalır.
Testler bunu gözle görülür kılar.

Planlanan ama henüz yazılmamış: `NetworkClient` için mock'lanmış yanıtlarla
entegrasyon testleri (401/404/timeout), UI testleri (kaynak ekleme akışı,
kategori-arama gezinmesi) ve gerçek sağlayıcılarla manuel testler.

### 13.1 Derleyicisiz doğrulanan mantık (`scripts/`)

VM'de Swift derleyicisi yoktur; bu yüzden sessizce yanlış davranabilecek karar
akışları **birebir Python portu** üzerinden CI'da sınanır:

| Betik | Sınadığı mantık |
|---|---|
| `seek_mantik_testi.py` | Tampon göstergesinin sarma boyunca açık kalması, "hedefe ulaşıldı" ölçütü, `.playing` için asgari bekleme |
| `iz_mantik_testi.py` | İz seçiminde kimlik temelli eşleşme, menü görünürlük ölçütü, "Kapalı" durumu, boş ad → numaralı etiket, durdurunca liste boşalması |

Bu ikisi `IPiosTests` içindeki Swift testlerinin **yerine geçmez**, tamamlayıcısıdır:
Swift testleri gerçek tipleri kullanır ama yalnızca CI'da koşar; portlar hızlıdır ve
mantığın okunabilir bir ifadesini tutar. İkisi ayrışırsa Swift tarafı doğrudur.

`static_check.py` ise derlemeden önce yapısal denetimler yapar: yerelleştirme anahtar
eşliği, MIMARI.md ağacının gerçek dosyalarla hizası, VLCKit sabitlemesi, oynatma
yolunun AVFoundation'a dönmemesi ve VLCKit köprüleme etiketlerinin doğru yazımı
(`withType` → `with` tuzağı, bkz. Bölüm 11.4).

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

