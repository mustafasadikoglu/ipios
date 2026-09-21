import Foundation

/// Tarih, süre ve sayı biçimlendirme yardımcıları.
enum Format {

    // MARK: - Süre

    /// Saniyeyi `1:23:45` veya `12:34` biçiminde gösterir.
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return L.t("format.duration.invalid") }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Yayın aralığı: `20:00 - 21:30`
    ///
    /// Ayırıcı da yerelleştirilir: bazı dillerde aralık tire yerine
    /// "20:00 – 21:30" gibi farklı bir işaretle yazılır.
    static func timeRange(from start: Date, to end: Date) -> String {
        L.f(
            "format.timeRange",
            timeFormatter.string(from: start),
            timeFormatter.string(from: end)
        )
    }

    /// İlerleme oranını yüzde olarak gösterir.
    static func percent(_ value: Double) -> String {
        String(format: "%%%d", Int((value * 100).rounded()))
    }

    // MARK: - Veri boyutu

    static func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Tarih

    /// Saat biçimi cihazın bölgesine uyum sağlar (`tr_TR`'de 20:00, `en_US`'te 8:00 PM).
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    /// "3 gün önce", "2 saat önce" gibi kaba bir geçmiş zaman ifadesi.
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Yüzde ilerleme metni: `%42`
    static func progress(_ value: Double) -> String {
        String(format: "%%%d", Int((min(max(value, 0), 1) * 100).rounded()))
    }
}
