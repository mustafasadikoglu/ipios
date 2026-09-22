# IPiOS

iOS için IPTV oynatıcı. Canlı TV, film ve dizi içeriklerini kullanıcının kendi
kaynağı (Xtream Codes hesabı veya M3U/M3U8 liste adresi) üzerinden oynatır.

Uygulama **içerik barındırmaz, sağlamaz, aramaz veya dağıtmaz**. Yalnızca bir
oynatıcıdır; eklenen kaynakların yasallığından kullanıcı sorumludur. Yasal uyarı
hem ilk açılışta hem de kaynak ekleme ekranında gösterilir.

---

## Gereksinimler

- macOS 13+ ve Xcode 15.3+ (iOS 16.0 SDK)
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

## GitHub üzerinden derleme

Mac'iniz olmasa da, hatta projeye hiç dokunmadan da kodun derlendiğini
görebilirsiniz: depoyu GitHub'a ittiğinizde `.github/workflows/ci.yml` otomatik
olarak çalışır. GitHub'ın `macos-15` runner'ı Xcode ile birlikte gelir, yani
derleme gerçekten Apple araç zinciriyle yapılır — bu, macOS olmayan bir
makinede yapılabilecek en sağlam doğrulamadır.

`macos-14` yerine `macos-15` seçilmiştir: macOS 14 imajı kullanımdan kaldırılmış
durumda ve beraberinde yalnızca Xcode 15.x taşıyor. Xcode 15'in iOS 18 simülatör
çalışma zamanı bulunmadığı için testler koşacak cihaz bulamıyordu. `macos-15`
imajı Xcode 16.x ile gelir ve iOS 18 çalışma zamanını içerir; test işi de tercih
listesinde önce iPhone 16 / iPad Pro (M4) gibi güncel cihazları dener.

`project.yml` içinde proje biçimi yine de sabitlenmiştir, çünkü proje hem CI'da
hem de yereldeki Xcode'da açılabilmelidir:

```yaml
options:
  projectFormat: xcode15_3   # objectVersion 63 — Xcode 15.3'ten 26.x'e kadar okunur
```

Sabitleme olmadan XcodeGen `xcode16_0` üretir ve Xcode 15.3–15.4 ile açılamaz.
`xcodeVersion` ayarı bunu **değiştirmez**: o yalnızca `LastUpgradeCheck`
damgasını etkiler, proje biçimini değil. CI, `project.pbxproj` içinde
`objectVersion = 63` olduğunu ayrıca doğrular, böylece ayar bir gün düşerse
hata derleme adımında
değil hemen orada ve anlaşılır biçimde görünür.

Akış üç aşamalıdır. Önce Ubuntu üzerinde `scripts/static_check.py` koşar ve
yerelleştirme eşliğini, kaynak yapısını, `Info.plist`'i ve doküman ağacını
denetler; burada bir hata çıkarsa pahalı macOS işi hiç başlatılmaz. Ardından
`xcodegen generate` ile proje üretilip `xcodebuild build` ile derlenir. Son
olarak `xcodebuild test` ile dört birim test dosyası çalıştırılır.

Sonuçları deponuzun **Actions** sekmesinden görebilirsiniz; kırmızı çarpı çıkan
bir çalışmaya tıklayıp başarısız adımın günlüğünü okumak, hatanın hangi
dosyada olduğunu gösterir.

**İmzalama gerekmez.** CI'da derleme `CODE_SIGNING_ALLOWED=NO` ile yapılır, bu
yüzden Apple Developer hesabı, sertifika veya `DEVELOPMENT_TEAM` ayarı
istemez. Bu ayarlar `project.yml` içine değil komut satırına verilir; yerel
imzalamanız bozulmaz. Test cihazı olarak sabit bir simülatör adı yerine,
runner'da kurulu olan ilk uygun cihaz seçilir.

Depo: <https://github.com/mustafasadikoglu/ipios>

Uzak sunucu zaten tanımlıdır. İlk itme:

```bash
git push -u origin main
```

GitHub 2021'den beri parola ile itmeye izin vermez; sorulduğunda **parola yerine
kişisel erişim jetonu (PAT)** girilir. `Settings → Developer settings →
Personal access tokens` yolundan `repo` kapsamıyla bir jeton üretilip parola
alanına yapıştırılır. Jetonu macOS Keychain'e kaydetmek için:

```bash
git config --global credential.helper osxkeychain
```

İş akışı `main` dalına itilen her commit'te, her pull request'te ve Actions
sekmesindeki **Run workflow** düğmesiyle elle tetiklenir. Aynı dala üst üste
itme yaparsanız önceki çalışma otomatik iptal edilir.

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

Bunlara ek olarak `scripts/static_check.py` derleyici gerektirmeyen bir denetim
yapar ve hem CI'da hem yerelde çalışır:

```bash
python3 scripts/static_check.py
```

Betik; iki dil arasındaki anahtar eşliğini, yer tutucu uyumunu, yinelenen ve
boş değerleri, süslü parantez dengesini, kapanmamış çok satırlı dizgeleri,
`Info.plist` geçerliliğini ve `docs/MIMARI.md` klasör ağacının gerçek dosya
listesiyle eşleşip eşleşmediğini kontrol eder. Sorun varsa `0` dışında bir çıkış
kodu döndürür, böylece CI doğrudan başarısız olur.

---

## Sağlayıcı teşhis aracı

Bir yayın açılmadığında sorunun uygulamada mı yoksa sağlayıcıda mı olduğunu
kesin olarak ayırt etmek için:

```bash
python3 scripts/xtream_teshis.py --url http://sunucu:8080 --user KULLANICI --pass PAROLA
```

Betik sağlayıcıya bağlanır ve şunları ölçer: kimlik durumu, üç içerik listesinin
(canlı/film/dizi) kayıt sayısı, film kayıtlarındaki alan tipleri (`cast`,
`director`, `genre` dizi olarak mı geliyor), bildirilen `container_extension`
değerleri ve en önemlisi **aynı içeriğin farklı uzantılarla gerçekten hangi
adreste açıldığı**. Sonunda iki ayrı liste verir: oynatmayı gerçekten durduran
engeller ve IPiOS'un zaten tolere ettiği tuhaflıklar.

Kimlik bilgisi betiğe yazılmaz, yalnızca komut satırından verilir ve hiçbir
dosyaya kaydedilmez. Çıktıyı paylaşırken sunucu adını ve kullanıcı adını
gizlemek için `--redact` ekleyin. Betik `0` dönerse sağlayıcı sağlamdır; sorun
uygulama tarafındadır.
