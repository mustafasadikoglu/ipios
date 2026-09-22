import Foundation
import VLCKit

/// libvlc'nin günlüğünden ve durumundan oynatma hatasının nedenini çıkarır.
///
/// Neden eski teşhisin yerini alıyor: `PlaybackDiagnostics` bir `AVPlayer`
/// kusurunu açıklamak için yazılmıştı ve nedeni **dolaylı** kanıtlardan
/// kestiriyordu (iz listesi okunur, `AVError` sayısal kodu çözümlenir).
/// VLCKit ile birlikte dolaylı kanıta gerek kalmıyor: libvlc başarısızlığın
/// nedenini kendi günlüğünde açıkça yazar — tanınmayan demuxer, desteklenmeyen
/// ses kodeği, reddedilen kimlik, zaman aşımı. Teşhis artık **okunuyor**,
/// tahmin edilmiyor.
///
/// Bu ayrım önemli çünkü VLC ile beklenen hata tablosu tümüyle değişti:
/// Matroska/AVI/MPEG-TS artık oynatılabildiği için "konteyner tanınmadı"
/// neredeyse hiç görülmez; buna karşılık **Türkiye'deki IPTV sağlayıcılarında
/// çok yaygın olan AC3/E-AC3/DTS ses** hâlâ sorun çıkarır. libvlc AC3'ü
/// çözebilir ama iOS'te yalnızca cihazın donanım çözücüsü varsa oynatır;
/// olmadığında ses çıkmaz ve günlüğe bunu yazar.
///
/// `PlaybackDiagnostics` **silinmedi**: `unsupportedAudio` kodek adları tablosu
/// ve `fourCC` çözümleyicisi burada yeniden kullanılır. Tek kaynak korunur ki
/// iki dosya arasında kodek adları birbirinden ayrışmasın.
enum VLCDiagnostics {

    // MARK: - Sınıflandırma

    /// libvlc günlüğünü ve ölçümü tek bir nedene indirger.
    ///
    /// Sıra önemlidir: en **kesin** kanıttan en zayıf tahmine inilir ve
    /// kullanıcının yapabileceği eylem belirleyicidir.
    ///
    /// 1. Sunucu reddi — sağlayıcı tarafında engel var, kullanıcı hesabını/
    ///    aboneliğini kontrol eder. Bu, "başka bir sürüm isteyin" demekten
    ///    tümüyle farklı bir eylemdir.
    /// 2. Yetkilendirme — kimlik reddedildi.
    /// 3. Zaman aşımı — sunucu hiç yanıt vermedi.
    /// 4. Ağ kopması — sunucuya ulaşılamadı.
    /// 5. Desteklenmeyen ses kodeği — ölçülen kodekten **kesin** kanıt.
    /// 6. Konteyner tanınmadı — libvlc'nin demuxer şikâyeti.
    /// 7. Ayırt edilemedi.
    ///
    /// - Parameters:
    ///   - profile: libvlc'den okunan akış profili (`nil` ise ölçüm yapılmadı).
    ///   - logLines: Oynatma oturumunda yakalanan sorun satırları.
    ///   - extensionHint: Teşhis metninde gösterilecek adres uzantısı.
    ///   - timedOut: Başlatma süresi aşıldı mı?
    static func classify(
        profile: VLCStreamProfile?,
        logLines: [String],
        extensionHint: String,
        timedOut: Bool
    ) -> PlaybackFailure {
        let haystack = logLines.joined(separator: "\n").lowercased()
        // Kullanıcıya gösterilecek teşhis satırı: dile bağlı olmayan kodlar.
        let code = technicalCode(logLines: logLines, profile: profile)

        // 1-2. Sunucu tarafı. Sağlayıcı reddi, kodek sorunundan **önce** gelir:
        // sunucu yayını vermediyse kodek hakkında hüküm verilemez.
        if let status = httpStatus(in: haystack) {
            if status == 401 || status == 403 {
                return PlaybackFailure(kind: .unauthorized, technicalCode: "HTTP \(status)")
            }
            if status >= 400 {
                return PlaybackFailure(kind: .rejected(status: status), technicalCode: "HTTP \(status)")
            }
        }
        if haystack.contains("401 unauthorized")
            || haystack.contains("403 forbidden")
            || haystack.contains("access denied")
            || haystack.contains("account is not active")
            || haystack.contains("expired") {
            return PlaybackFailure(kind: .unauthorized, technicalCode: code)
        }

        // 3-4. Ağ katmanı.
        if timedOut || haystack.contains("timed out") || haystack.contains("timeout") {
            return PlaybackFailure(kind: .timedOut, technicalCode: code)
        }
        if haystack.contains("could not connect")
            || haystack.contains("connection refused")
            || haystack.contains("no route to host")
            || haystack.contains("network is unreachable")
            || haystack.contains("name resolution")
            || haystack.contains("unable to resolve") {
            return PlaybackFailure(kind: .offline, technicalCode: code)
        }

        // 5. Ses kodeği **kanıtlanmış** sorun mu?
        //
        //    Burada ölçülen kodeğin kendisi hüküm vermez: libvlc AC3, E-AC3,
        //    DTS, TrueHD ve Opus'u yazılım çözücüleriyle çözer. Yalnızca bir
        //    kodek görüldü diye "çözülemiyor" demek, `AVPlayer` döneminden
        //    kalan ve artık geçerli olmayan bir varsayımdır. Hüküm yalnızca
        //    libvlc'nin bu konuda **şikâyet ettiği** durumda verilir.
        if let profile, let name = profile.audioBurdenedName,
           let evidence = audioFailureEvidence(in: haystack, codecKeys: profile.audioCodecKeys) {
            return PlaybackFailure(
                kind: .unsupportedAudioCodec(name: name),
                technicalCode: "\(profile.technicalSummary) ← \(evidence)"
            )
        }

        // 6. Konteyner: libvlc demuxer bulamadığını söylüyor.
        if haystack.contains("no suitable demux module")
            || haystack.contains("cannot recognize")
            || haystack.contains("unrecognized")
            || haystack.contains("could not detect")
            || haystack.contains("unknown format") {
            return PlaybackFailure(
                kind: .unrecognizedContainer(extensionHint: extensionHint),
                technicalCode: code
            )
        }

        // 7. Ayırt edilemedi. Teşhis satırı yine de boş bırakılmaz: kanıt
        //    yokluğunun kendisi bilgidir.
        return PlaybackFailure(kind: .unknown, technicalCode: code.isEmpty ? "vlc" : code)
    }

    /// Oynatma sırasında **başladıktan sonra** kesilme için teşhis.
    ///
    /// Ayrım önemli: burada "yayın açılamadı" demek yanlış olurdu — yayın
    /// açılmıştı, kesildi. Ayırt edilebilen bir neden (sunucu reddi, ağ
    /// kopması) varsa o gösterilir; yoksa "yayın kesildi" metni kullanılır.
    static func classifyInterruption(logLines: [String]) -> PlaybackFailure {
        let failure = classify(
            profile: nil,
            logLines: logLines,
            extensionHint: "",
            timedOut: false
        )
        if case .unknown = failure.kind {
            return PlaybackFailure(
                kind: .interrupted,
                technicalCode: failure.technicalCode
            )
        }
        // Zaman aşımı ve ağ kopması burada da "kesildi" anlamına gelir; neden
        // korunur ama kullanıcıya kesilme olarak bildirilir.
        switch failure.kind {
        case .timedOut, .offline:
            return PlaybackFailure(kind: .interrupted, technicalCode: failure.technicalCode)
        default:
            return failure
        }
    }

    // MARK: - Yardımcılar

    /// Ses kodeğinin gerçekten sorun çıkardığına dair libvlc günlüğündeki kanıt.
    ///
    /// İki parçalı bir ölçüt aranır: günlükte **hem** bir başarısızlık ifadesi
    /// **hem** sorunlu kodeğin adı geçmelidir. Yalnızca "failed" görmek yetmez —
    /// o satır video çözücüsüne ait olabilir; yalnızca kodek adını görmek de
    /// yetmez — libvlc o kodeği başarıyla açtığını da yazmış olabilir ("using
    /// audio decoder", "AC3 audio").
    ///
    /// Bu çift ölçüt, `AVPlayer` dönemindeki "kodek tabloda varsa çalınamaz"
    /// varsayımının yerini alır: o varsayım libvlc için yanlış teşhis üretirdi.
    ///
    /// - Returns: Eşleşen kanıt cümlesi; kanıt yoksa `nil`.
    private static func audioFailureEvidence(in haystack: String, codecKeys: [String]) -> String? {
        // Yalnızca **açıkça olumsuz** ifadeler. "audio decoder" gibi nötr bir
        // kalıp listeye konmamalıdır: libvlc bir çözücüyü başarıyla yüklediğinde
        // de "using audio decoder module" yazar ve o satır bir sorun bildirimi
        // değildir. Böyle bir kalıp, çalışan bir yayında sahte hüküm üretirdi.
        let failurePhrases = [
            "no suitable audio decoder",
            "failed to create audio decoder",
            "cannot decode audio",
            "could not decode audio",
            "failed to decode audio",
            "no decoder for",
            "decoder not found",
        ]
        guard let phrase = failurePhrases.first(where: { haystack.contains($0) }) else {
            return nil
        }
        // Kanıt cümlesi sesle ilgili olmalı: "decoder not found" tek başına
        // görüntü çözücüsü için de yazılır, o hâlde ses kodeği adı ayrıca
        // aranır.
        guard codecKeys.contains(where: { haystack.contains($0) }) else { return nil }
        return phrase
    }

    /// Günlükten HTTP durum kodunu çıkarır.
    ///
    /// libvlc durum kodunu serbest metin içinde bildirir (ör. "HTTP 403
    /// Forbidden" ya da "error: HTTP 404"). Yalnızca bilinen kalıba uyan ilk
    /// kod alınır; ilgisiz sayıların kod sanılması önlenir.
    private static func httpStatus(in haystack: String) -> Int? {
        guard let range = haystack.range(of: "http ") else { return nil }
        let rest = haystack[range.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        guard digits.count == 3, let value = Int(digits) else { return nil }
        return value
    }

    /// Kullanıcıya iletilebilecek, dile bağlı olmayan teşhis satırı.
    ///
    /// Hata düzeyindeki ilk satırlar seçilir: libvlc'nin gürültülü `debug`
    /// satırları (buffer okundu, modül yüklendi) teşhis değeri taşımaz ve
    /// kullanıcıya gösterilecek metni okunamaz hâle getirir.
    private static func technicalCode(logLines: [String], profile: VLCStreamProfile?) -> String {
        var parts: [String] = []
        if let profile { parts.append(profile.technicalSummary) }

        // libvlc satırları "hata:" / "hatası:" önekini zaten taşır; yalnızca
        // en fazla birkaç tanesi alınır.
        let notable = logLines
            .filter { !$0.isEmpty }
            .suffix(3)
        if !notable.isEmpty {
            parts.append(notable.joined(separator: " · "))
        }
        return parts.joined(separator: " ← ")
    }

    // MARK: - Ölçüm

    /// Oynatıcıdan akışın gerçekte ne taşıdığını okur.
    ///
    /// `VLCMedia` düzeyinde **dört harfli** kodek kimlikleri bulunur
    /// (`fourcc`); `VLCMediaPlayer.Track` ise kodeğin Türkçe kullanıcı için
    /// anlamlı adını (`codecName()`, ör. "AC-3 audio") verir. İkisi birlikte
    /// kullanılır: fourcc eşlemeyi (hangi kodek desteklenmiyor) belirler,
    /// `codecName` sağlayıcıya iletilecek metni üretir.
    ///
    /// Ölçüm başlatma başarısız olduktan **sonra** yapılır; başarılı
    /// oynatmada gereksiz iş çıkarılmaz.
    static func profile(of player: VLCMediaPlayer) -> VLCStreamProfile? {
        // Önce oynatıcı izleri: bunlar çözülen (demux edilen) gerçek kodekleri
        // verir. `VLCMediaPlayer.Track`, `VLCMedia.Track`'in alt sınıfı
        // olduğu için `fourcc`/`codecName()` burada da geçerlidir.
        var audio: [String] = []
        var video: [String] = []

        for track in player.audioTracks {
            if let name = trackName(track, codecFourcc: track.fourcc) {
                audio.append(name)
            }
        }
        for track in player.videoTracks {
            if let name = trackName(track, codecFourcc: track.fourcc) {
                video.append(name)
            }
        }

        // Oynatıcı hiç iz bildirmediyse (başlatma demuxer aşamasında düştüyse)
        // medya düzeyine inilir: `tracksInformation` parse edilmiş medyadan
        // kodek bilgisi verir.
        if audio.isEmpty, video.isEmpty, let media = player.media {
            for track in media.tracksInformation {
                let isAudio = track.type == .audio
                let isVideo = track.type == .video
                guard isAudio || isVideo else { continue }
                guard let name = trackName(track, codecFourcc: track.fourcc) else { continue }
                if isAudio { audio.append(name) } else { video.append(name) }
            }
        }

        guard !audio.isEmpty || !video.isEmpty else { return nil }

        return VLCStreamProfile(
            audioCodecs: dedupe(audio),
            videoCodecs: dedupe(video)
        )
    }

    /// Bir izin okunabilir kodek adını üretir.
    ///
    /// Öncelik sırası: `codecName()` (libvlc'nin kendi adı, ör. "AC-3 audio")
    /// → fourcc'den çözülen ad → fourcc'nin ham hâli. Hiçbiri yoksa `nil`
    /// döner ve iz atlanır; uydurma bir ad yazmaktansa izi atlamak doğrudur.
    private static func trackName(_ track: VLCMedia.Track, codecFourcc: UInt32) -> String? {
        let provided = track.codecName()
        if !provided.isEmpty { return provided }

        let fourcc = PlaybackDiagnostics.fourCC(codecFourcc).lowercased()
        if !fourcc.isEmpty, fourcc != "????" { return fourcc }
        return nil
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// libvlc'den ölçülen akış profili.
///
/// `StreamInspection`'ın VLC karşılığı. Ayrı tip tutulur çünkü `isReadable`
/// kavramı burada **yoktur**: libvlc tanımadığı konteyner için zaten
/// "no suitable demux module" satırını yazar, dolayısıyla "iz yok" ile
/// "taşıyıcı okunamadı" ayrımını yapmaya gerek kalmaz.
struct VLCStreamProfile: Equatable {

    /// Okunabilir ses kodek adları (ör. "AC-3 audio", "MPEG AAC Audio").
    var audioCodecs: [String] = []
    var videoCodecs: [String] = []

    /// Okunan ses kodeklerinin eşleştirmede kullanılacak **küçük harfli**
    /// anahtarları.
    ///
    /// Günlükte bu adların geçip geçmediğini aramak için kullanılır: libvlc
    /// sorunu kendi cümlesiyle bildirirken kodeği de adıyla anar, dolayısıyla
    /// iki bilgiyi eşleştirmek gerekir.
    var audioCodecKeys: [String] {
        audioCodecs.map { $0.lowercased() }
    }

    /// Okunan ses kodeğinin kullanıcıya söylenecek adı.
    ///
    /// **Adı "desteklenmeyen" değildir**, çünkü bu özellik bir hüküm vermez:
    /// libvlc bu kodeklerin tamamını yazılım çözücüleriyle oynatır. Ad, yalnızca
    /// sorun **kanıtlandığında** kullanıcıya hangi kodekten söz edildiğini
    /// söylemek için üretilir.
    ///
    /// `nil` ise ses izi okunamadı ya da kodek tabloda yok. Kodeğin tanınmaması
    /// bir sorun değildir; yalnızca adlandırılamaz.
    var audioBurdenedName: String? {
        for codec in audioCodecs {
            let key = codec.lowercased()
            // Kodek adı libvlc'den "ac-3 audio" gibi gelebilir; dört harfli
            // parça aranır. Anahtar sözlüğü kısa kodlar taşıdığı için "içeriyor"
            // karşılaştırması gerekir.
            for (fourcc, family) in PlaybackDiagnostics.audioCodecNames
            where key.contains(fourcc) {
                return Self.refinedName(for: key, family: family)
            }
        }
        return nil
    }

    /// Aile adını, biliniyorsa daha kesin profille değiştirir.
    ///
    /// Ayrım kullanıcı için önemli: DTS'in düz, HD ve Express sürümleri farklı
    /// altyapı gerektirir ve sağlayıcıya söylenecek şey de farklıdır. Ancak
    /// eşleme yalnızca **kesin bilinen** kalıplarda yapılır; tanınmayan bir
    /// DTS varyantı için aile adı ("DTS") bırakılır. Yanlış bir sürüm adı
    /// söylemek, genel ad söylemekten kötüdür.
    private static func refinedName(for codec: String, family: String) -> String {
        switch family {
        case "DTS":
            if codec.contains("dts-hd") || codec.contains("dtshd") || codec.contains("dtsh") {
                return "DTS-HD"
            }
            if codec.contains("dts express") || codec.contains("dtse") {
                return "DTS Express"
            }
            return "DTS"
        case "E-AC3":
            // libvlc E-AC3'ü "eac3" ya da "ec-3" olarak yazar; ikisi de aynı.
            return "E-AC3"
        case "AC3":
            return "AC3"
        default:
            return family
        }
    }

    /// Teşhis satırı için ölçülen kodekler (dile bağlı olmayan).
    var technicalSummary: String {
        var parts: [String] = []
        if !videoCodecs.isEmpty { parts.append("V:" + videoCodecs.joined(separator: "+")) }
        if !audioCodecs.isEmpty { parts.append("A:" + audioCodecs.joined(separator: "+")) }
        return parts.joined(separator: " ")
    }
}
