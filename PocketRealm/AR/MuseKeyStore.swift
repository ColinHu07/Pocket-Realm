import Foundation
import Security

enum MuseKeyStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hacklanta.PocketRealm.muse",
        kSecAttrAccount as String: "api-key"
    ]

    static func read() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw storageError }
        return key
    }

    static func save(_ key: String) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains(where: { $0.isWhitespace }) else {
            throw PlanError.server("Paste the API key by itself, without spaces.")
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(clean.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw storageError }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw storageError }
    }

    private static var storageError: PlanError {
        .server("Couldn't access the iPhone Keychain. Unlock your phone and try again.")
    }
}

/// Keys remain in separate Keychain services; choosing a provider never copies a key.
enum PlannerKeyStore {
    static func read(for provider: PlanningProvider) throws -> String? {
        switch provider {
        case .muse: return try MuseKeyStore.read()
        case .gemini: return try GeminiKeyStore.read()
        }
    }
    static func save(_ key: String, for provider: PlanningProvider) throws {
        switch provider {
        case .muse: try MuseKeyStore.save(key)
        case .gemini: try GeminiKeyStore.save(key)
        }
    }
    static func remove(for provider: PlanningProvider) throws {
        switch provider {
        case .muse: try MuseKeyStore.remove()
        case .gemini: try GeminiKeyStore.remove()
        }
    }
}
