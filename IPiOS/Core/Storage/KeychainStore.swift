import Foundation
import Security

/// Xtream şifreleri gibi hassas verileri Keychain'de saklar.
///
/// Şifreler hiçbir zaman `UserDefaults` veya JSON dosyasına yazılmaz.
enum KeychainStore {
    private static let service = "com.mustafa.ipios.credentials"

    /// Metinler de `Localizable.strings` içinden gelir: bu hata bir gün
    /// ekrana taşınırsa kullanıcı Türkçe sabit bir cümle değil, çevrilmiş
    /// bir mesaj görmelidir.
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case dataConversion

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return L.f("error.keychain", status)
            case .dataConversion:
                return L.t("error.keychain.conversion")
            }
        }
    }

    // MARK: - Yazma / Okuma / Silme

    static func save(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversion
        }
        // Aynı anahtar varsa önce silinir, sonra eklenir.
        try? delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func exists(_ key: String) -> Bool {
        read(key) != nil
    }
}
