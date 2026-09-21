import XCTest
@testable import IPiOS

/// Yerelleştirme dosyalarının bütünlüğünü doğrular.
///
/// Uygulamanın kuralı: kullanıcıya görünen hiçbir metin kodda sabit yazılmaz,
/// hepsi `L.t` / `L.f` üzerinden gelir. Bu kural sessizce bozulabilir (bir
/// anahtar yanlış yazılır, çevirilerden biri güncellenmez) ve ekranda
/// "player.action.pip" gibi ham bir anahtar görünene kadar fark edilmez.
/// Buradaki testler o hataları derleme zamanında değil, test zamanında yakalar.
final class LocalizationTests: XCTestCase {

    private enum Lang: String, CaseIterable {
        case tr
        case en

        /// `Localizable.strings` dosyasının yolu.
        ///
        /// - Important: `Bundle(for:)` test paketini (`.xctest`) döner ve
        ///   yerelleştirme dosyaları orada **değildir**; onlar ana uygulama
        ///   paketindedir. Bu yüzden sırayla birkaç paket denenir: test
        ///   paketi (dosyalar oraya da kopyalanmışsa), ana uygulama paketi ve
        ///   son çare olarak yüklü tüm paketler. Tek bir pakete güvenmek,
        ///   testin sessizce hiçbir dosya bulamamasına yol açardı.
        var path: String? {
            for bundle in Self.candidateBundles {
                if let found = bundle.path(
                    forResource: "Localizable",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: rawValue
                ) {
                    return found
                }
            }
            return nil
        }

        /// Denenecek paketler, sırayla.
        ///
        /// - Note: `Bundle.allBundles` / `Bundle.allFrameworks` yalnızca
        ///   macOS'ta vardır, iOS'ta derlenmez; bu yüzden burada kullanılmaz.
        ///   Test paketi barındıran uygulama (host app) ile çalıştığında
        ///   `Bundle.main` zaten ana uygulama paketidir ve dosyaları içerir.
        private static var candidateBundles: [Bundle] {
            var bundles: [Bundle] = [Bundle(for: LocalizationTests.self)]
            let main = Bundle.main
            if !bundles.contains(where: { $0.bundlePath == main.bundlePath }) {
                bundles.append(main)
            }
            if let app = Bundle(identifier: "com.mustafa.ipios"),
               !bundles.contains(where: { $0.bundlePath == app.bundlePath }) {
                bundles.append(app)
            }
            return bundles
        }
    }

    /// `"anahtar" = "değer";` satırlarından anahtar listesi çıkarır.
    private func keys(inFileAt path: String) -> [String] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var keys: [String] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""),
                  let equals = trimmed.firstIndex(of: "="),
                  let closing = trimmed.dropFirst().firstIndex(of: "\"") else { continue }
            let key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closing])
            if trimmed.index(after: closing) <= equals || equals > closing {
                keys.append(key)
            }
        }
        return keys
    }

    /// Bir değerdeki biçim belirteçlerini (`%@`, `%d`, `%02d`) çıkarır.
    private func placeholders(in value: String) -> [String] {
        var found: [String] = []
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "%" else {
                index = value.index(after: index)
                continue
            }
            var probe = value.index(after: index)
            var token = "%"
            while probe < value.endIndex, "0123456789$".contains(value[probe]) {
                token.append(value[probe])
                probe = value.index(after: probe)
            }
            if probe < value.endIndex, "@dfs".contains(value[probe]) {
                token.append("@dfs".contains(value[probe]) ? String(value[probe]) : "")
                found.append(token)
                index = value.index(after: probe)
            } else {
                index = value.index(after: probe)
            }
        }
        return found.sorted()
    }

    private func dictionary(for lang: Lang) throws -> [String: String] {
        let path = try XCTUnwrap(lang.path, "\(lang.rawValue) yerelleştirme dosyası bulunamadı")
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        var result: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"") else { continue }
            let parts = trimmed.split(separator: "\"", omittingEmptySubsequences: false)
            guard parts.count >= 4 else { continue }
            let key = String(parts[1])
            let value = String(parts[3])
            result[key] = value
        }
        return result
    }

    // MARK: - Testler

    func testBothLocalizationsExist() throws {
        for lang in Lang.allCases {
            XCTAssertNotNil(lang.path, "\(lang.rawValue) dosyası yok")
        }
    }

    /// İki dildeki anahtar kümeleri birebir aynı olmalı.
    func testKeyParityBetweenTurkishAndEnglish() throws {
        let tr = try dictionary(for: .tr)
        let en = try dictionary(for: .en)

        let onlyTR = Set(tr.keys).subtracting(en.keys)
        let onlyEN = Set(en.keys).subtracting(tr.keys)

        XCTAssertTrue(onlyTR.isEmpty, "Yalnızca Türkçe'de olan anahtarlar: \(onlyTR.sorted())")
        XCTAssertTrue(onlyEN.isEmpty, "Yalnızca İngilizce'de olan anahtarlar: \(onlyEN.sorted())")
    }

    /// Aynı anahtar bir dosyada iki kez tanımlanmamalı.
    /// Yinelenen tanım, ilk değerin sessizce yok sayılmasına yol açar.
    func testNoDuplicateKeys() throws {
        for lang in Lang.allCases {
            let path = try XCTUnwrap(lang.path)
            let all = keys(inFileAt: path)
            let duplicates = Set(all.filter { key in all.filter { $0 == key }.count > 1 })
            XCTAssertTrue(duplicates.isEmpty, "\(lang.rawValue) yinelenen anahtarlar: \(duplicates.sorted())")
        }
    }

    /// Biçim belirteçleri iki dilde aynı olmalı; aksi hâlde `String(format:)`
    /// yanlış argümanla çalışır ya da çöker.
    func testPlaceholderParity() throws {
        let tr = try dictionary(for: .tr)
        let en = try dictionary(for: .en)

        for key in Set(tr.keys).intersection(en.keys) {
            let a = placeholders(in: tr[key] ?? "")
            let b = placeholders(in: en[key] ?? "")
            XCTAssertEqual(a, b, "\(key) için yer tutucular farklı — tr: \(a), en: \(b)")
        }
    }

    /// Hiçbir değer boş olmamalı; boş değer ekranda boş satır bırakır.
    func testNoEmptyValues() throws {
        for lang in Lang.allCases {
            let dict = try dictionary(for: lang)
            let empty = dict.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertTrue(empty.isEmpty, "\(lang.rawValue) boş değerler: \(empty.keys.sorted())")
        }
    }

    /// Çözülemeyen anahtar anahtarın kendisini döner. Kritik akışlarda bunun
    /// olmadığını doğrudan sınarız.
    func testCriticalKeysResolve() {
        let critical = [
            "startup.error", "startup.retry", "player.error.title",
            "error.playbackFailed", "legal.title", "onboarding.title",
            "sources.synced.value", "settings.legal.body"
        ]
        for key in critical {
            XCTAssertNotEqual(L.t(key), key, "\(key) anahtarı çözülemedi")
        }
    }

    /// Biçimli metin çağrısı argümanı doğru yerleştirmeli.
    func testFormattedTextSubstitutesArguments() {
        let message = L.f("error.server", 503)
        XCTAssertTrue(message.contains("503"), "Sunucu kodu mesaja girmeli: \(message)")
        XCTAssertFalse(message.contains("%d"), "Biçim belirteci çözülmemiş: \(message)")
    }
}
