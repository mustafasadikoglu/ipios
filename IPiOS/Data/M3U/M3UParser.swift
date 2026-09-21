import Foundation

/// M3U / M3U8 playlist dosyalarını `#EXTINF` tabanlı olarak ayrıştırır.
///
/// Tipik bir kayıt:
/// ```
/// #EXTINF:-1 tvg-id="trt1.tr" tvg-name="TRT 1" tvg-logo="http://…/trt1.png" group-title="Ulusal",TRT 1
/// http://server/live/user/pass/101.m3u8
/// ```
///
/// Ayrıştırıcı bilinçli olarak hoşgörülüdür: eksik attribute, tırnaksız değer,
/// fazladan boş satır, BOM ve CRLF gibi durumlarda çökmeden devam eder.
struct M3UParser {

    /// Ayrıştırılmış ham kayıt.
    struct Entry: Hashable {
        var title: String
        var url: URL
        var groupTitle: String?
        var tvgID: String?
        var tvgName: String?
        var logoURL: URL?
        var durationRaw: String?
        /// `#EXTGRP` direktifiyle gelen grup (group-title yoksa kullanılır).
        var extGroup: String?
        /// Kaynak dosyadaki sıra numarası.
        var index: Int

        /// Sıralama/önceleme için en anlamlı başlık.
        var effectiveTitle: String {
            if !title.isEmpty { return title }
            if let tvgName, !tvgName.isEmpty { return tvgName }
            return url.lastPathComponent
        }

        var effectiveGroup: String? {
            if let groupTitle, !groupTitle.isEmpty { return groupTitle }
            if let extGroup, !extGroup.isEmpty { return extGroup }
            return nil
        }
    }

    /// Ayrıştırma sonucu.
    struct Result {
        var entries: [Entry]
        /// Dosyadaki benzersiz grup adları (sıralı).
        var groupNames: [String]

        var isEmpty: Bool { entries.isEmpty }
    }

    // MARK: - Public API

    /// Metni ayrıştırır.
    static func parse(_ text: String) -> Result {
        var entries: [Entry] = []
        entries.reserveCapacity(2048)

        var pendingTitle = ""
        var pendingAttributes: [String: String] = [:]
        var pendingDuration: String?
        var pendingExtGroup: String?
        var isExtendedLine = false
        var index = 0

        // Satır sonlarını normalize et ve BOM'u temizle.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF") {
                let parsed = parseExtInf(line)
                pendingTitle = parsed.title
                pendingAttributes = parsed.attributes
                pendingDuration = parsed.duration
                isExtendedLine = true
                continue
            }

            if line.hasPrefix("#EXTGRP:") {
                pendingExtGroup = String(line.dropFirst("#EXTGRP:".count))
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            // Diğer direktifler (#EXTM3U, #KODIPROP, #EXTVLCOPT …) atlanır.
            if line.hasPrefix("#") { continue }

            // Bu satır bir URL olmalı.
            guard let url = URL(string: line), url.scheme != nil else {
                // Göreli veya bozuk adres: kaydı atlarız ama ayrıştırmayı sürdürürüz.
                isExtendedLine = false
                continue
            }

            let entry = Entry(
                title: isExtendedLine ? pendingTitle : "",
                url: url,
                groupTitle: pendingAttributes["group-title"],
                tvgID: pendingAttributes["tvg-id"],
                tvgName: pendingAttributes["tvg-name"],
                logoURL: (pendingAttributes["tvg-logo"] ?? pendingAttributes["logo"]).flatMap {
                    guard !$0.isEmpty else { return nil }
                    return URL(string: $0)
                },
                durationRaw: pendingDuration,
                extGroup: pendingExtGroup,
                index: index
            )
            entries.append(entry)
            index += 1

            // Durumu sıfırla.
            pendingTitle = ""
            pendingAttributes = [:]
            pendingDuration = nil
            pendingExtGroup = nil
            isExtendedLine = false
        }

        // Grup adlarını sıralı ve benzersiz biçimde çıkar.
        var seen = Set<String>()
        var groups: [String] = []
        for entry in entries {
            guard let group = entry.effectiveGroup, !seen.contains(group) else { continue }
            seen.insert(group)
            groups.append(group)
        }

        return Result(entries: entries, groupNames: groups)
    }

    // MARK: - #EXTINF satırı

    private struct ParsedExtInf {
        var title: String = ""
        var attributes: [String: String] = [:]
        var duration: String?
    }

    /// `#EXTINF:-1 tvg-id="x" group-title="y",Başlık` satırını çözer.
    ///
    /// Sınır, tırnakların dışındaki **ilk** virgüldür. Başlığın kendisi virgül
    /// içerebilir (örneğin "Haber, Spor") — o virgüller sınırdan sonra kaldığı
    /// için başlığa dahil olur.
    private static func parseExtInf(_ line: String) -> ParsedExtInf {
        var result = ParsedExtInf()
        var body = String(line.dropFirst("#EXTINF".count))

        if body.hasPrefix(":") {
            body = String(body.dropFirst())
        }

        // Virgülden önceki kısım süre + attribute'lar, sonrası başlıktır.
        // Başlık virgül içerebildiği için sınır **ilk** virgüldür — ancak
        // yalnızca tırnakların *dışındaki* ilk virgül. Tırnak içindeki virgül
        // bir attribute değerinin parçasıdır; oradan bölmek hem değeri keser
        // (`tvg-id="abc,Kanal` -> `abc`) hem de değerin kalanını başlık yapar.
        let head: String
        if let commaIndex = firstUnquotedComma(in: body) {
            head = String(body[body.startIndex..<commaIndex])
            let tail = String(body[body.index(after: commaIndex)...])
            result.title = tail.trimmingCharacters(in: .whitespaces)
        } else {
            head = body
        }

        // Süre, baştaki ilk simge öbeğidir (`-1`, `0`, bazen `120`). Yalnızca
        // sayısal görünen bir öbek süre kabul edilir; aksi hâlde süre alanı boş
        // kalır ve öbek attribute sanılmasın diye yine gövdeden çıkarılır.
        let tokens = head.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if let first = tokens.first,
           first.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }) {
            result.duration = String(first)
        }

        // Süre öbeği attribute ayrıştırmasından **önce** gövdeden çıkarılmalı.
        // Aksi hâlde `-1 tvg-id="x"` girdisinde anahtar `-1 tvg-id` olur,
        // boşluk içerdiği için reddedilir ve tarama her `=` işaretini atlayarak
        // tüm attribute'ları (logo, kategori, EPG kimliği) kaybeder.
        if let spaceIndex = head.firstIndex(of: " ") {
            body = String(head[head.index(after: spaceIndex)...])
        } else {
            body = ""
        }

        result.attributes = parseAttributes(body)

        // Bazı listelerde başlık boş olur ve `tvg-name` kullanılır.
        if result.title.isEmpty, let tvgName = result.attributes["tvg-name"] {
            result.title = tvgName
        }

        return result
    }

    /// Tırnakların dışındaki ilk virgülün konumu; yoksa `nil`.
    ///
    /// Kaçış dizisi (`\"`) desteklenmez: M3U listelerinde görülmez ve görmek
    /// yerine satırı hoşgörüyle ayrıştırmak daha güvenlidir.
    private static func firstUnquotedComma(in text: String) -> String.Index? {
        var insideQuotes = false
        for index in text.indices {
            let character = text[index]
            if character == "\"" {
                insideQuotes.toggle()
            } else if character == ",", !insideQuotes {
                return index
            }
        }
        return nil
    }

    /// `key="value"` veya `key=value` çiftlerini çıkarır.
    ///
    /// Değer içinde boşluk olabileceği için tırnaklı değerler önceliklidir.
    private static func parseAttributes(_ input: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var index = input.startIndex

        while index < input.endIndex {
            // Anahtarı oku.
            guard let equals = input[index...].firstIndex(of: "=") else { break }

            let key = input[index..<equals]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            // Boşluk içeren "anahtar" gerçek bir attribute değildir; atlanır.
            guard !key.isEmpty, !key.contains(" ") else {
                index = input.index(after: equals)
                continue
            }

            var valueStart = input.index(after: equals)
            guard valueStart < input.endIndex else { break }

            var value: String
            if input[valueStart] == "\"" {
                // Tırnaklı değer: kapanış tırnağını bul.
                valueStart = input.index(after: valueStart)
                if let closing = input[valueStart...].firstIndex(of: "\"") {
                    value = String(input[valueStart..<closing])
                    index = input.index(after: closing)
                } else {
                    // Kapanış tırnağı yok: satır sonuna kadar al.
                    value = String(input[valueStart...])
                    index = input.endIndex
                }
            } else {
                // Tırnaksız: sonraki boşluğa kadar.
                let end = input[valueStart...].firstIndex(of: " ") ?? input.endIndex
                value = String(input[valueStart..<end])
                index = end
            }

            value = value.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty {
                attributes[key] = value
            }
        }

        return attributes
    }
}
