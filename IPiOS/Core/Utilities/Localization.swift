import Foundation

/// Kullanıcıya görünen tüm metinlerin tek giriş noktası.
///
/// Neden gerekli: metinler kodun içine gömülürse hem yerelleştirme hem de
/// yazım düzeltmesi dağınık hâle gelir. `L.t(...)` / `L.f(...)` çağrıları
/// `IPiOS/Resources/<dil>.lproj/Localizable.strings` dosyalarındaki
/// anahtarlara karşılık gelir.
///
/// Anahtar bulunamazsa `NSLocalizedString` anahtarın kendisini döner; bu
/// sayede eksik çeviri sessizce kaybolmaz, ekranda `live.title` gibi görünür.
enum L {

    /// Argümansız metin.
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /// Biçimlendirilmiş metin. Örn: `L.f("format.duration.hoursMinutes", 1, 42)`
    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
    }
}
