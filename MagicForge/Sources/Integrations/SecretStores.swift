import Foundation
import MFCore
import MFUtilities
#if canImport(Security)
import Security
#endif

public enum SecretStoreError: Error, Equatable, Sendable {
    /// A Keychain call failed with this `OSStatus`.
    case keychain(status: Int32, message: String)
    /// The stored item is not UTF-8 text.
    case unreadableValue
}

/// Volatile store for tests, previews and platforms without a Keychain. Nothing is persisted.
public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let values: Locked<[String: String]>

    public init(_ initial: [String: String] = [:]) { values = Locked(initial) }

    public func secret(for account: String) throws -> String? { values.current[account] }

    /// Nil or an empty string removes the secret.
    public func setSecret(_ value: String?, for account: String) throws {
        values.withLock { store in
            if let value, !value.isEmpty { store[account] = value } else { store[account] = nil }
        }
    }
}

#if canImport(Security)
/// Generic-password Keychain items: `kSecAttrService` = `service`, `kSecAttrAccount` = account.
/// Items are readable after first unlock and never leave this device (no iCloud Keychain sync,
/// not included in backups restored to another Mac).
public final class KeychainSecretStore: SecretStoring, @unchecked Sendable {
    private let service: String

    public init(service: String) { self.service = service }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Returns nil when no item exists.
    public func secret(for account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Self.error(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.unreadableValue
        }
        return value
    }

    /// Adds or updates the item. Nil or an empty string deletes it (deleting a missing item succeeds).
    public func setSecret(_ value: String?, for account: String) throws {
        let query = baseQuery(account: account)
        guard let value, !value.isEmpty else {
            let status: OSStatus = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
            return
        }

        // The accessibility class is set when the item is created; updates only replace the value.
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus: OSStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw Self.error(updateStatus) }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus: OSStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Self.error(addStatus) }
    }

    private static func error(_ status: OSStatus) -> SecretStoreError {
        let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        return .keychain(status: Int32(status), message: message)
    }
}
#endif
