import Foundation

/// Oynatılan içerikte bulunan tek bir ses ya da altyazı izi.
///
/// **Neden ayrı bir model:** `VLCMediaPlayer.Track` doğrudan arayüze taşınamaz.
/// O nesneler libvlc'nin iz listesinden **her okumada yeniden üretilir** —
/// yerel kaynağa bakıldı, `VLCMediaPlayer (Tracks)` kategorisi her çağrıda yeni
/// bir dizi ve yeni nesneler döndürüyor. Yani SwiftUI içinde o nesneyi
/// `Identifiable` yapıp listeye koymak, her yenilemede kimliği değişen bir liste
/// üretirdi ve seçim "kayar". Bu yüzden arayüze yalnızca **kararlı** alanlar
/// taşınır: libvlc'nin iz kimliği (`trackId`) ve okunabilir ad.
struct PlaybackTrack: Identifiable, Equatable, Sendable {

    /// libvlc'nin iz kimliği. Seçim **bu değerle** yapılır; nesne kimliğiyle
    /// değil. Kimliğin uygulama ömrü boyunca kararlı olduğu libvlc tarafından
    /// `idStable` ile bildirilir, ancak biz yine de kimliği metin olarak saklarız.
    let id: String

    /// Kullanıcıya gösterilecek ad.
    ///
    /// libvlc'nin `trackName` alanı çoğu dosyada **boş** gelir; gömülü
    /// altyazılarda ise genelde dil kodu bulunur. Bu yüzden ad her zaman
    /// doldurulur: boşsa **görünüm katmanı** sıra numarasıyla anlamlı bir etiket
    /// üretir ("Altyazı 2"). Etiket burada üretilmez çünkü yerelleştirilmiş
    /// metin gerekir ve model katmanı `L.t` çağırmaz.
    let name: String

    /// İzin dili (varsa). Örnek: `tur`, `eng`.
    let language: String?

    /// İz türü. Arayüz ses ve altyazı listelerini bu alanla ayırır.
    let kind: Kind

    /// Aynı içerikteki kaçıncı iz olduğu (0 tabanlı). Adı boş izleri
    /// numaralandırarak ayırt etmek için gerekir: "Altyazı 2" gibi.
    let ordinal: Int

    enum Kind: String, Sendable {
        case audio
        case subtitle
    }

    init(id: String, name: String, language: String?, kind: Kind, ordinal: Int) {
        self.id = id
        self.name = name
        self.language = language
        self.kind = kind
        self.ordinal = ordinal
    }

    /// İzin **adı boş mu?**
    ///
    /// Gömülü izlerin çoğunda libvlc `trackName` alanını boş bırakır; görünüm bu
    /// durumda sıra numarasıyla bir etiket üretir ("Altyazı 2"). Ölçüt burada
    /// tutulur ki karar tek yerde verilsin ve görünüm katmanı kendi kuralını
    /// yazmasın. **Etiketin kendisi burada üretilmez:** metin yerelleştirilmiş
    /// olmalıdır ve model katmanı `L.t` çağırmaz.
    var hasEmptyName: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Sıra numarasından (0 tabanlı) kullanıcıya gösterilecek sıra (1 tabanlı).
    /// Arayüz etiketinde doğrudan kullanılır; `+ 1` görünümün içine dağılmasın.
    var displayOrdinal: Int { ordinal + 1 }
}

/// Bir içerikte bulunan izlerin tümü ve o an seçili olanlar.
///
/// Motor bu yapıyı **her okumada yeniden üretir**; arayüz yalnızca bunu
/// yayınlanan bir değer olarak görür. Birleştirme mantığı buradadır çünkü
/// derleyicisiz doğrulanabilen yegâne parçadır (bkz. `scripts/iz_mantik_testi.py`)
/// ve SwiftUI tarafında tekrar yazılırsa iki farklı davranış doğar.
struct PlaybackTrackSet: Equatable, Sendable {

    var audio: [PlaybackTrack] = []
    var subtitles: [PlaybackTrack] = []

    /// Seçili ses izinin kimliği. `nil` ise ses izi seçili değil (nadir ama
    /// olabilir: bozuk dosyalarda libvlc hiçbir ses izini seçmez).
    var selectedAudioID: String?

    /// Seçili altyazı izinin kimliği. `nil` ise altyazı **kapalıdır** —
    /// bu, kullanıcının açıkça seçebileceği geçerli bir durumdur.
    var selectedSubtitleID: String?

    static let empty = PlaybackTrackSet()

    /// Seçilebilecek ses izi var mı?
    var hasAudioChoice: Bool { audio.count > 1 }

    /// Altyazı var mı? (Altyazıyı kapatma seçeneği her zaman sunulur, bu
    /// yüzden ölçüt "en az bir iz" olmasıdır.)
    var hasSubtitleChoice: Bool { !subtitles.isEmpty }

    /// İzin listedeki sırası. Bulunamazsa `nil`.
    ///
    /// Neden sıra gerekiyor: seçim için `player.selectTrack(at:type:)` indeks
    /// ister. İndeksi arayüzde hesaplamak, liste ile motor arasındaki sıralamanın
    /// ayrışmasına açık kapı bırakırdı.
    func index(of id: String, in kind: PlaybackTrack.Kind) -> Int? {
        list(for: kind).firstIndex { $0.id == id }
    }

    func list(for kind: PlaybackTrack.Kind) -> [PlaybackTrack] {
        switch kind {
        case .audio: return audio
        case .subtitle: return subtitles
        }
    }

    /// Seçili ses izi. Yoksa `nil`.
    var selectedAudio: PlaybackTrack? { audio.first { $0.id == selectedAudioID } }

    /// Seçili altyazı izi. Altyazı kapalıysa `nil`.
    var selectedSubtitle: PlaybackTrack? { subtitles.first { $0.id == selectedSubtitleID } }

    /// Aynı anda hem seçilebilir ses hem altyazı var mı? Kontrol katmanındaki
    /// iz düğmesinin çizilip çizilmeyeceğini belirler. Tek bir izi olan ve
    /// altyazısı olmayan içerikte menü açmak kullanıcıya seçenek sunmaz.
    var hasAnyChoice: Bool { hasAudioChoice || hasSubtitleChoice }
}
