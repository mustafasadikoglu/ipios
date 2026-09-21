import Foundation

/// XMLTV (`tvguide.xml`, `epg.xml`) formatını **akış tabanlı** ayrıştırır.
///
/// Neden `XMLParser` (SAX) ve `XMLDocument` (DOM) değil: XMLTV dosyaları
/// tipik olarak 50–200 MB arasıdır ve DOM yaklaşımı cihaz belleğini tüketir.
/// `XMLParser` olay güdümlü çalıştığı için dosya boyutundan bağımsız olarak
/// sabit bellekle ayrıştırma yapılır.
///
/// Örnek biçim:
/// ```xml
/// <tv>
///   <channel id="trt1.tr"><display-name>TRT 1</display-name></channel>
///   <programme start="20260921200000 +0300" stop="20260921210000 +0300" channel="trt1.tr">
///     <title lang="tr">Ana Haber</title>
///     <desc lang="tr">Günün gelişmeleri.</desc>
///     <category>Haber</category>
///   </programme>
/// </tv>
/// ```
final class XMLTVParser: NSObject {

    /// Ayrıştırma sonucu.
    struct Output {
        /// Kanal kimliği -> görünen ad.
        var channelNames: [String: String] = [:]
        /// Kanal kimliği -> programlar (başlangıca göre sıralı).
        var programsByChannel: [String: [EPGProgram]] = [:]
        /// Dosyadaki toplam program sayısı.
        var programCount: Int = 0
    }

    /// `stop` alanı olmayan yayınlar için varsayılan süre (saniye).
    var defaultProgramDuration: TimeInterval = 1800

    private let parser: XMLParser
    private var output = Output()

    // Ayrıştırma durumu — `programme` ve `channel` elemanları arasında geçiş yapılır.
    private enum Context {
        case none
        case channel
        case programme
    }

    private var context: Context = .none
    private var currentElement = ""
    private var textBuffer = ""

    // Kanal durumu
    private var currentChannelID: String?
    private var currentChannelName: String?

    // Program durumu
    private var currentProgramChannel: String?
    private var currentProgramStart: String?
    private var currentProgramStop: String?
    private var currentProgramTitle: String?
    private var currentProgramSubTitle: String?
    private var currentProgramDescription: String?
    private var currentProgramCategory: String?

    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    convenience init?(contentsOf url: URL) {
        guard let stream = InputStream(url: url) else { return nil }
        self.init(stream: stream)
    }

    private init(stream: InputStream) {
        self.parser = XMLParser(stream: stream)
        super.init()
        self.parser.delegate = self
    }

    // MARK: - Public API

    /// Dosyayı baştan sona ayrıştırır.
    ///
    /// - Parameter filter: Yalnızca verilen kanal kimlikleri saklanır.
    ///   `nil` ise tüm kanallar alınır. Bellek tasarrufu için filtre önerilir.
    func parse(filter: Set<String>? = nil) -> Output {
        // `shouldKeep` kapanışı delegate üzerinden erişilebilir olmalı.
        self.filter = filter
        let success = parser.parse()
        if !success {
            Log.epg.error("XMLTV ayristirma hatasi: \(String(describing: self.parser.parserError), privacy: .public)")
        }
        return output
    }

    private var filter: Set<String>?

    // MARK: - Yardımcılar

    /// XMLTV zaman damgasını `Date`'e çevirir.
    ///
    /// Kabul edilen biçimler: `20260921200000 +0300`, `20260921200000`, `202609212000 +0300`.
    static func parseXMLTVDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ").map(String.init)

        // İlk öbek tarih damgası (14 veya 12 hane), ikinci öbek saat dilimidir.
        guard let stamp = parts.first, stamp.count >= 12 else { return nil }

        // Saat dilimi kaydırması: "+0300", "-0500". Yarım saatlik dilimler
        // (Hindistan +0530) da bu hesapta doğru çıkar.
        var timeZoneOffset = 0
        if parts.count > 1 {
            let offset = parts[1]
            let sign = offset.hasPrefix("-") ? -1 : 1
            let digits = offset.filter(\.isNumber)
            if digits.count == 4,
               let hours = Int(digits.prefix(2)),
               let minutes = Int(digits.suffix(2)) {
                timeZoneOffset = sign * (hours * 3600 + minutes * 60)
            }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: timeZoneOffset) ?? TimeZone(secondsFromGMT: 0)

        // Saniye varsa saniyeyi koru; yoksa dakika hassasiyetine düş.
        // `dateFormat` burada mutlaka atanmalı — `DateFormatter` varsayılan
        // biçimi bölgeye bağlıdır ve "yyyyMMdd…" damgasını çözemez.
        let attempts: [(String, Int)] = [("yyyyMMddHHmmss", 14), ("yyyyMMddHHmm", 12)]
        for (format, length) in attempts where stamp.count >= length {
            formatter.dateFormat = format
            if let date = formatter.date(from: String(stamp.prefix(length))) {
                return date
            }
        }
        return nil
    }
}

// MARK: - XMLParserDelegate

extension XMLTVParser: XMLParserDelegate {

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        textBuffer = ""

        switch elementName {
        case "channel":
            context = .channel
            currentChannelID = attributeDict["id"]
            currentChannelName = nil

        case "programme":
            // Filtre varsa ve bu kanal istenmiyorsa program bloğunu tamamen atla.
            let channel = attributeDict["channel"] ?? ""
            if let filter, !filter.contains(channel) {
                context = .none
                return
            }
            context = .programme
            currentProgramChannel = channel
            currentProgramStart = attributeDict["start"]
            currentProgramStop = attributeDict["stop"]
            currentProgramTitle = nil
            currentProgramSubTitle = nil
            currentProgramDescription = nil
            currentProgramCategory = nil

        case "title", "sub-title", "desc", "category", "display-name":
            // Metin `foundCharacters` ile toplanır.
            break

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // Bazı dosyalar çok parçalı karakter olayı gönderir; birleştirilir.
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer { currentElement = "" }
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (context, elementName) {
        case (.channel, "display-name"):
            if currentChannelName == nil, !text.isEmpty {
                currentChannelName = text
            }

        case (.channel, "channel"):
            if let id = currentChannelID {
                output.channelNames[id] = currentChannelName ?? id
            }
            currentChannelID = nil
            currentChannelName = nil
            context = .none

        case (.programme, "title"):
            if currentProgramTitle == nil, !text.isEmpty { currentProgramTitle = text }

        case (.programme, "sub-title"):
            if currentProgramSubTitle == nil, !text.isEmpty { currentProgramSubTitle = text }

        case (.programme, "desc"):
            if currentProgramDescription == nil, !text.isEmpty { currentProgramDescription = text }

        case (.programme, "category"):
            if currentProgramCategory == nil, !text.isEmpty { currentProgramCategory = text }

        case (.programme, "programme"):
            appendCurrentProgram()
            context = .none

        default:
            break
        }
    }

    private func appendCurrentProgram() {
        guard let channel = currentProgramChannel,
              let startRaw = currentProgramStart,
              let start = XMLTVParser.parseXMLTVDate(startRaw) else {
            return
        }

        let end: Date
        if let stopRaw = currentProgramStop, let parsedEnd = XMLTVParser.parseXMLTVDate(stopRaw) {
            end = parsedEnd
        } else {
            end = start.addingTimeInterval(defaultProgramDuration)
        }

        guard end > start else { return }

        // Adı olmayan bir programı tamamen atlamak yerine yer tutucu adla
        // yayın akışında gösteriyoruz: kullanıcı için "boşluk" değil,
        // "bilgi yok" demek daha anlaşılır. Metin yerelleştirilmiştir.
        let title = currentProgramTitle ?? L.t("live.guide.untitled")
        let program = EPGProgram(
            id: "\(channel)-\(Int(start.timeIntervalSince1970))",
            channelID: channel,
            title: title,
            subtitle: currentProgramSubTitle,
            description: currentProgramDescription,
            start: start,
            end: end,
            category: currentProgramCategory
        )

        output.programsByChannel[channel, default: []].append(program)
        output.programCount += 1
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        Log.epg.error("XMLTV parse hatasi: \(parseError.localizedDescription, privacy: .public)")
    }
}
