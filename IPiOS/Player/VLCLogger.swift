import Foundation
import VLCKit

/// libvlc'nin kendi günlüğünü yakalayan köprü.
///
/// Neden gerekli: `AVPlayer` döneminde oynatma hatasının nedeni ancak
/// **dolaylı** yollarla öğrenilebiliyordu (iz listesi okunur, `AVError` kodu
/// çözümlenir, sunucu yanıtı ölçülür). Bu yöntemler üç tur boyunca "Oynatma
/// başlatılamadı." cümlesinden öteye geçemedi. libvlc ise başarısızlığın
/// nedenini **kendi ağzından** söyler: hangi modülün yüklendiğini, demuxer'ın
/// dosyayı tanıyıp tanımadığını, ağ isteğinin hangi durum kodunu aldığını
/// satır satır yazar.
///
/// Bu yüzden günlük yalnızca hata ayıklama kolaylığı değil, **teşhis
/// kaynağıdır**: `VLCDiagnostics` gerçek nedeni buradan okur.
///
/// `VLCLogging` protokolüne doğrudan uyulur, `VLCConsoleLogger` alt sınıflanmaz.
/// Neden: alt sınıflama `override` gerektirir ve protokol yönteminin Swift'e
/// hangi imzayla köprülendiği sürüme göre değişebilir; protokolü doğrudan
/// uygulamak bu tahmini tümüyle ortadan kaldırır ve yalnızca iki üye ister.
@objc final class VLCLogger: NSObject, VLCLogging {

    /// `VLCLogLevel` değerleri (`VLCLogging.h`): 0 = hata, 1 = uyarı,
    /// 2 = bilgi, 3 = ayrıntılı. Sayısal değerler **bilinçli** olarak
    /// kullanılır: NS_ENUM sabitlerinin Swift adları (`kVLCLogLevelError` →
    /// `.error`) sürüme göre değişebilir, sayısal değerler değişmez.
    private enum LevelValue {
        static let warning: Int32 = 1
        static let debug: Int32 = 3
    }

    /// Yakalanan tek bir günlük satırı.
    struct Entry: Sendable, Equatable {
        let level: Int32
        let message: String
    }

    /// Tek örnek. libvlc günlüğü süreç genelindedir; oynatıcı başına ayrı
    /// logger kurmak aynı satırların çoklanmasına yol açardı.
    static let shared = VLCLogger()

    /// Saklanan azami satır sayısı.
    private let capacity = 400

    /// Yalnızca uyarı ve hata düzeyindeki satırlar. Bunlar `capacity` sınırına
    /// takılmaz: sorunun nedeni neredeyse her zaman burada durur ve kritik
    /// satırın, sıradan bir "buffer okundu" satırı yüzünden düşmesi kabul
    /// edilemez.
    private var problems: [Entry] = []

    /// Son satırlar (halka tampon).
    private var recent: [Entry] = []

    /// Farklı iş parçacıklarından yazılabilir; kilit zorunlu.
    private let lock = NSLock()

    private override init() {
        super.init()
        // Teşhis için "info" bile yetersiz kalabilir: tanınmayan taşıyıcıya
        // ilişkin satırlar `debug` düzeyinde gelir.
        level = VLCLogLevel(rawValue: LevelValue.debug) ?? .debug
    }

    // MARK: - VLCLogging

    var level: VLCLogLevel = .debug

    func handleMessage(_ message: String, logLevel level: VLCLogLevel, context: VLCLogContext?) {
        let entry = Entry(level: level.rawValue, message: message)

        lock.lock()
        if level.rawValue <= LevelValue.warning {
            // Hata (0) ve uyarı (1) kalıcı olarak saklanır.
            problems.append(entry)
            // Yalnızca sorun satırları biriken bir liste de sınırsız büyümesin.
            if problems.count > capacity {
                problems.removeFirst(problems.count - capacity)
            }
        }
        recent.append(entry)
        if recent.count > capacity {
            recent.removeFirst(recent.count - capacity)
        }
        lock.unlock()
    }

    // MARK: - Okuma

    /// Yeni bir oynatma oturumu için birikmiş günlüğü temizler.
    ///
    /// Neden: önceki yayının günlüğü yeni yayının teşhisine karışırsa, çoktan
    /// çözülmüş bir sorun "şu anki neden" gibi okunur ve kullanıcı yanlış yöne
    /// gönderilir.
    func reset() {
        lock.lock()
        problems.removeAll(keepingCapacity: true)
        recent.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    /// Bu oturumda yakalanan sorun satırları (uyarı + hata).
    func problemLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return problems.map(\.message)
    }
}
