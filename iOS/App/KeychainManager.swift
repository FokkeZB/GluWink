import CryptoKit
import Foundation
import os
import SharedKit

final class KeychainManager {
    static let shared = KeychainManager()

    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "KeychainManager")
    private let service = Constants.bundlePrefix
    private let account = "settings-passphrase"

    private init() {}

    /// Whether a passphrase has been stored.
    var hasPassphrase: Bool {
        read() != nil
    }

    /// Store a new passphrase (hashed with SHA-256 + random salt).
    func setPassphrase(_ passphrase: String) {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let hash = Self.hash(passphrase, salt: salt)
        let stored = salt + hash
        write(stored)
    }

    /// Verify a passphrase against the stored hash. Returns false if no passphrase is set.
    func verify(_ passphrase: String) -> Bool {
        guard let stored = read(), stored.count == 48 else { return false }
        let salt = stored.prefix(16)
        let expectedHash = stored.suffix(32)
        let hash = Self.hash(passphrase, salt: salt)
        return hash == expectedHash
    }

    /// Remove the stored passphrase.
    func removePassphrase() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete failed: \(status)")
        }
    }

    // MARK: - EasyView password

    /// The user's EasyView login password. Stored in Keychain so it never
    /// leaves the main app. The session cookie is stored in the App Group
    /// (accessible to widget + watch) and re-acquired from this password on
    /// expiry.
    var easyViewPassword: String? {
        get { readString(account: "easyview-password") }
        set { writeOrDelete(string: newValue, account: "easyview-password") }
    }

    // MARK: - LibreLinkUp credentials

    var libreLinkUpEmail: String? {
        get { readString(account: "librelinkup-email") }
        set { writeOrDelete(string: newValue, account: "librelinkup-email") }
    }

    var libreLinkUpPassword: String? {
        get { readString(account: "librelinkup-password") }
        set { writeOrDelete(string: newValue, account: "librelinkup-password") }
    }

    var libreLinkUpToken: String? {
        get { readString(account: "librelinkup-token") }
        set { writeOrDelete(string: newValue, account: "librelinkup-token") }
    }

    var libreLinkUpTokenExpiry: Date? {
        get {
            guard let iso = readString(account: "librelinkup-token-expiry") else { return nil }
            return ISO8601DateFormatter().date(from: iso)
        }
        set {
            writeOrDelete(string: newValue?.ISO8601Format(), account: "librelinkup-token-expiry")
        }
    }

    // MARK: - Private helpers

    private func readString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeOrDelete(string: String?, account: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        guard let string, !string.isEmpty, let data = string.data(using: .utf8) else { return }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain write failed for '\(account)': \(status)")
        }
    }

    // MARK: - Passphrase private

    private static func hash(_ passphrase: String, salt: Data) -> Data {
        let input = salt + Data(passphrase.utf8)
        let digest = SHA256.hash(data: input)
        return Data(digest)
    }

    private func write(_ data: Data) {
        removePassphrase()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain write failed: \(status)")
        }
    }

    private func read() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}
