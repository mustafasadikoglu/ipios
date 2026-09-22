import Foundation
import UIKit

/// Oynatma başarısızlığının **kullanıcıya dönük** sözlüğü.
///
/// Bu dosya artık iki şeyi tutar: başarısızlık türleri (`PlaybackFailureKind`)
/// ve kodek adları tablosu. Neden ayrı duruyor: sınıflandırmayı yapan mantık
/// VLC'ye taşındı (`VLCDiagnostics`), ama kullanıcıya gösterilen metinler ve
/// kodek adları motordan bağımsızdır. İki ayrı yerde tutulsalardı bir gün
/// ayrışırlar ve örneğin `ac-3` bir dosyada "AC3", diğerinde "AC-3" olurdu.
///
/// **Motordan bağımsız kalanlar burada:** kodek tablosu, `fourCC` çözümleyicisi,
/// sağlayıcıya gönderilen User-Agent. **Motora bağlı olanlar** ilgili motorun
/// dosyasında: akış ölçümü ve günlük çözümlemesi (`VLCDiagnostics`).
///
/// Tarihçe: bu dosyada bir zamanlar `AVPlayer`'a özel bir sınıflandırma
/// (`classify`), `AVError` kod eşlemesi ve `AVURLAsset` ile akış okuma
/// (`inspect`) bulunuyordu. Sağlayıcının filmleri yalnızca Matroska olarak
/// sunması ve `AVFoundation`'ın Matroska demuxer'ının olmaması nedeniyle
/// oynatma çekirdeği VLCKit'e taşındı; o kod tamamen kaldırıldı. Kaldırmak
/// yerine bırakmak tehlikeli olurdu: çağrılmayan bir sınıflandırma, "hâlâ
/// kullanılıyor" sanılıp yanlış teşhis üretirdi.
enum PlaybackFailureKind: Equatable {
    /// Ses kodeği cihazda çözülemiyor.
    ///
    /// `VLCKit` ile bu tablo **daraldı ama kaybolmadı**: libvlc AC3/E-AC3/DTS
    /// akışlarını çözebilir, ancak iOS'te sesin gerçekten çalması cihazın
    /// desteklediği biçime bağlıdır. Türkiye'deki IPTV sağlayıcılarında bu
    /// kodekler çok yaygın olduğu için kullanıcının göreceği en olası hata
    /// budur ve eylemi nettir: sağlayıcıdan sesi AAC olan bir sürüm istemek.
    case unsupportedAudioCodec(name: String)
    /// Görüntü kodeği cihazda çözülemiyor.
    case unsupportedVideoCodec(name: String)
    /// Taşıyıcı biçim tanınamadı.
    case unrecognizedContainer(extensionHint: String)
    /// Sunucu yayını vermeyi reddetti (ör. 404, 5xx).
    case rejected(status: Int)
    /// Sunucu kimliği kabul etmedi.
    case unauthorized
    /// Sunucuya ulaşılamadı.
    case offline
    /// Sunucu zamanında yanıt vermedi.
    case timedOut
    /// Yayın açıldıktan **sonra** kesildi.
    ///
    /// "Başlatılamadı"dan ayrı tutulur çünkü kullanıcının deneyimi farklıdır:
    /// yayın bir süre oynadı ve düştü. Aynı metni kullanmak, kullanıcıyı
    /// hiç açılmamış bir yayını tekrar tekrar denemeye yönlendirirdi.
    case interrupted
    /// Hiçbiri ayırt edilemedi.
    case unknown
}

/// Sınıflandırılmış başarısızlık: kullanıcıya gösterilecek **açıklama** ve
/// teşhis için **kod**.
struct PlaybackFailure: Equatable {

    let kind: PlaybackFailureKind

    /// Yalnızca kodlardan oluşan, dile bağlı olmayan teşhis satırı.
    ///
    /// Neden kod: hata metinleri İngilizce gelir ve Türkçe arayüzde anlamsız
    /// bir gürültüdür. Kodek adı + durum kodu ise dilden bağımsızdır ve
    /// doğrudan aranabilir (`ac-3`, `HTTP 403`).
    let technicalCode: String

    /// Kullanıcıya gösterilecek tam metin.
    var message: String {
        switch kind {
        case .unsupportedAudioCodec(let name):
            return L.f("player.error.codec.audio", name)
        case .unsupportedVideoCodec(let name):
            return L.f("player.error.codec.video", name)
        case .unrecognizedContainer(let hint):
            return L.f("player.error.container", hint.isEmpty ? "—" : hint)
        case .rejected(let status):
            // Durum kodu okunamadıysa (0) "%d" yerine kodsuz metin gösterilir;
            // "kod: 0" demek kullanıcıyı yanıltırdı.
            return status > 0
                ? L.f("player.error.rejected", status)
                : L.t("player.error.rejectedNoCode")
        case .unauthorized:
            return L.t("error.unauthorized")
        case .offline:
            return L.t("error.sourceUnreachable")
        case .timedOut:
            return L.t("player.error.timeout")
        case .interrupted:
            return L.t("player.error.interrupted")
        case .unknown:
            return L.t("player.error.startFailed")
        }
    }

    /// Açıklama + teşhis satırı. Teşhis yoksa yalnızca açıklama döner; boş
    /// satır ya da "Teknik: " artığı bırakılmaz.
    var fullMessage: String {
        guard !technicalCode.isEmpty else { return message }
        return L.f("player.error.technical", message, technicalCode)
    }
}

/// Oynatma çekirdeğinin sağlayıcıya kendini tanıttığı sabitler ve kodek
/// sözlüğü.
enum PlaybackDiagnostics {

    /// Sağlayıcıya gönderilen uygulama adı.
    ///
    /// Bazı paneller tanımadıkları istemcileri engeller. Teşhis araçları da
    /// (`scripts/xtream_teshis.py`) **aynı** adı göndermek zorundadır; farklı
    /// bir ad gönderilseydi ölçüm gerçek oynatma koşulunu yansıtmazdı ve
    /// "sunucu uygulamayı engelliyor" teşhisi yanlış çıkardı.
    static let userAgent = "IPiOS/1.0 (iOS)"

    /// libvlc'ye HTTP başlığı olarak verilecek User-Agent'ın anahtarı.
    ///
    /// `:http-user-agent` libvlc'nin kendi seçeneğidir; `VLCMedia.addOption`
    /// ile medya başına verilir (bkz. `VLCPlayerEngine.startItem(with:)`).
    static let userAgentOptionKey = ":http-user-agent"

    /// Ses kodeklerinin kullanıcıya söylenecek **adları**.
    ///
    /// Anahtarlar dört harfli kodek kimlikleridir (libvlc'nin `codecName()` ya
    /// da `fourcc` çıktısı küçük harfe çevrilerek aranır). Tablo
    /// `VLCDiagnostics` içinde **tek kaynak** olarak kullanılır.
    ///
    /// **Bu tablonun anlamı VLC'ye geçişle birlikte değişti.** Adı eskiden
    /// "desteklenmeyen ses kodekleri" idi ve `AVFoundation` bu kodekleri
    /// çözemediği için liste bir **hüküm** taşıyordu: bu kodek görülürse oynatma
    /// başarısızdır. libvlc ise AC3, E-AC3, DTS (tüm varyantları), TrueHD ve
    /// Opus'u **yazılım çözücüleriyle** çözer. Aynı listeyi hüküm olarak
    /// kullanmak artık **yanlış teşhis** üretirdi: kullanıcıya "sağlayıcıdan AAC
    /// isteyin" denir, oysa gerçek sorun bambaşka bir yerdedir.
    ///
    /// Bu yüzden tablo bugün yalnızca **adlandırma** sözlüğüdür; bir kodek
    /// burada olması onun çalınamayacağı anlamına gelmez. Sorun bildirimi
    /// libvlc'nin kendi günlüğündeki kanıta bağlanmıştır
    /// (bkz. `VLCDiagnostics.classify`, 5. adım).
    static let audioCodecNames: [String: String] = [
        "ac-3": "AC3",
        "ec-3": "E-AC3",
        "eac3": "E-AC3",
        // Düz DTS de listede **olmak zorunda**: libvlc bu kodeği
        // çoğunlukla "DTS audio" olarak adlandırır ve dört harfli kimlik her
        // zaman elde edilemez. "dts" anahtarı olmadan düz DTS hiç tanınmazdı.
        // Sıra önemsizdir: `refinedName` hangi anahtar önce gelirse gelsin
        // doğru varyantı üretir.
        "dts": "DTS",
        "dtsc": "DTS",
        "dtsh": "DTS-HD",
        "dtsl": "DTS",
        "dtse": "DTS Express",
        "mlpa": "TrueHD",
        "opus": "Opus",
    ]

    /// Görüntü kodeklerinin adları. Ses tablosuyla aynı gerekçeyle artık bir
    /// **hüküm değil**, adlandırma sözlüğüdür: libvlc AV1, VP9 ve VP8'i de
    /// çözer.
    static let videoCodecNames: [String: String] = [
        "av01": "AV1",
        "vp09": "VP9",
        "vp08": "VP8",
    ]

    /// Dört harfli kodek kimliğini okunabilir metne çevirir.
    ///
    /// Yazdırılamayan baytlar `?` olur; böylece bozuk bir kimlik metni
    /// parantez içinde çöp karakterlerle doldurmaz.
    static func fourCC(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        let characters: [Character] = bytes.map { byte in
            (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "?"
        }
        return String(characters).trimmingCharacters(in: .whitespaces)
    }
}
