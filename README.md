# IPiOS

iOS için IPTV oynatıcı. Canlı TV, film ve dizi içeriklerini kullanıcının kendi
kaynağı (Xtream Codes hesabı veya M3U/M3U8 liste adresi) üzerinden oynatır.

Uygulama **içerik barındırmaz, sağlamaz, aramaz veya dağıtmaz**. Yalnızca bir
oynatıcıdır; eklenen kaynakların yasallığından kullanıcı sorumludur. Yasal uyarı
hem ilk açılışta hem de kaynak ekleme ekranında gösterilir.

---

## Gereksinimler

- macOS 13+ ve Xcode 15+ (iOS 16.0 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- Hedef: iOS 16.0 ve üzeri, iPhone + iPad

Projede **üçüncü taraf bağımlılık yoktur**; her şey SwiftUI, AVKit ve standart
Foundation API'leriyle yazılmıştır. `Package.swift`, Podfile veya SPM paketi
bulunmaz.

---

## Kurulum

Depoda `.xcodeproj` dosyası **bilerek tutulmaz**. Proje tanımı `project.yml`
dosyasındadır ve Xcode projesi ondan üretilir; böylece hedef ayarları, dosya
listesi ve derleme yapılandırması okunabilir tek bir metin dosyasında kalır ve
birleştirme (merge) çakışmaları oluşmaz.

```bash
cd ipios
xcodegen generate
open IPiOS.xcodeproj
```

`IPiOS.xcodeproj` üretilen bir çıktıdır, sürüm kontrolüne eklenmez.

---

## Derleme ve çalıştırma

```bash
# Komut satırından derleme
xcodebuild -project IPiOS.xcodeproj -scheme IPiOS -destination 'platform=iOS Simulator,name=iPhone 15' build

# Birim testleri
xcodebuild -project IPiOS.xcodeproj -scheme IPiOS -destination 'platform=iOS Simulator,name=iPhone 15' test
```

Xcode arayüzünde: `IPiOS` şemasını seçip çalıştırın. İmzalama için
`project.yml` içindeki `DEVELOPMENT_TEAM` alanına kendi takım kimliğinizi yazıp
`xcodegen generate` komutunu tekrar çalıştırın.

---

## İlk kullanım

1. Uygulama açıldığında yasal uyarı ekranı gelir; kabul edilmeden devam edilemez.
2. **Kaynak Ekle** ekranından bir kaynak tanımlanır:
   - **Xtream Codes:** sunucu adresi (port dahil), kullanıcı adı, şifre
   - **M3U / M3U8:** liste adresi (dosyadan seçim de desteklenir)
   - İsteğe bağlı olarak bir EPG (XMLTV) adresi
3. **Bağlantıyı Test Et** ile kaynak doğrulanır, ardından kaydedilir.
4. Kaynak aktif yapıldığında içerik listesi arka planda indirilir ve sekmeler dolar.

---

## Özellikler

Canlı TV, kategoriler ve arama; EPG (şimdi/sırada, ilerleme çubuğu, kanal bazlı
yayın akışı); film ve dizi kataloğu (sezon/bölüm gezintisi); favoriler; son
izlenenler ve kaldığı yerden devam; Picture-in-Picture desteği.

---

## Yerelleştirme

Birincil dil Türkçe, ikincil dil İngilizce. Kullanıcıya görünen hiçbir metin koda
gömülü değildir; hepsi `L.t("anahtar")` / `L.f("anahtar", argümanlar)` üzerinden
`Localizable.strings` dosyasından gelir.

```
IPiOS/Resources/tr.lproj/Localizable.strings   # birincil
IPiOS/Resources/en.lproj/Localizable.strings   # ikincil
IPiOS/Resources/tr.lproj/InfoPlist.strings     # Info.plist metinleri
IPiOS/Resources/en.lproj/InfoPlist.strings
```

`Info.plist` içindeki kullanıcıya görünen metinler (örneğin yerel ağ izni istemi)
`Localizable.strings` ile **yerelleştirilemez**: sistem bu metinleri uygulama daha
başlamadan okur ve yalnızca `InfoPlist.strings` dosyasına bakar. Bu yüzden ayrı
dosyalarda tutulurlar.

Yeni bir metin eklerken iki dile de aynı anahtarı yazmak gerekir. Anahtar sayısı,
yer tutucu uyumu ve tanımsız anahtar kontrolü `IPiosTests/LocalizationTests.swift`
içindeki testlerle korunur.

---

## Güvenlik

- Şifreler yalnızca **Keychain**'e (`kSecClassGenericPassword`) yazılır.
- `PlaylistSource` modeli düz metin şifre alanı taşımaz; yalnızca Keychain
  kaydının anahtarını tutar.
- `UserDefaults` (`AppSettings`) yalnızca hassas olmayan tercihleri saklar.
- Xtream adreslerindeki `username` / `password` sorgu parametreleri log'a
  yazılmadan önce maskelenir (`Logger.redacted`).

---

## Proje yapısı

Katmanlar: `Views` → `ViewModels` → `Domain` ← `Data`, artı her katmanın
kullanabildiği `Core` ve `Player`. Ayrıntılı klasör ağacı, katman kuralları ve
tasarım kararları için [`docs/MIMARI.md`](docs/MIMARI.md) dosyasına bakın.

---

## Testler

`IPiosTests` hedefinde dört dosya bulunur:

- `M3UParserTests.swift` — bozuk satırlar, eksik attribute, çoklu adres, BOM/CRLF
- `XMLTVDateTests.swift` — XMLTV zaman damgası ve saat dilimi dönüşümleri
- `CoreUtilitiesTests.swift` — biçimleyiciler (süre, aralık, yüzde, dosya boyutu)
- `LocalizationTests.swift` — anahtar eşliği, yer tutucu uyumu, tanımsız anahtar
