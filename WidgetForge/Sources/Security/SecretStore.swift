import Foundation
#if canImport(Security)
import Security
#endif

// Storage for API keys and tokens. Widgets never receive secret values: the data engine substitutes
// `{{secret:NAME}}` placeholders into outgoing requests after the host allowlist has been checked.

/// A stored credential together with the only hosts it may ever be sent to.
///
/// Binding a secret to hosts matters for imported widgets: approving a widget's network allowlist must not
/// let it attach *your* GitHub token to a request for *its* server.
struct Secret: Codable, Equatable, Sendable {
    var value: String
    var hosts: [String]
}

protocol SecretStore: AnyObject {
    func secret(named name: String) -> Secret?
    /// Pass nil to delete.
    func setSecret(_ secret: Secret?, named name: String) throws
    func secretNames() -> [String]
}

final class InMemorySecretStore: SecretStore {
    private var values: [String: Secret]
    private let lock = NSLock()
    init(_ values: [String: Secret] = [:]) { self.values = values }

    func secret(named name: String) -> Secret? { lock.lock(); defer { lock.unlock() }; return values[name] }
    func setSecret(_ secret: Secret?, named name: String) throws { lock.lock(); defer { lock.unlock() }; values[name] = secret }
    func secretNames() -> [String] { lock.lock(); defer { lock.unlock() }; return values.keys.sorted() }
}

#if canImport(Security)
struct KeychainError: Error, LocalizedError {
    var status: OSStatus
    var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

/// Generic-password items in the user's login keychain, scoped to this app's service name.
final class KeychainSecretStore: SecretStore {
    let service: String
    init(service: String = "com.widgetforge.app.secrets") { self.service = service }

    private func baseQuery(_ name: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let name { q[kSecAttrAccount as String] = name }
        return q
    }

    func secret(named name: String) -> Secret? {
        var q = baseQuery(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Secret.self, from: data)
    }

    func setSecret(_ secret: Secret?, named name: String) throws {
        let q = baseQuery(name)
        guard let secret, !secret.value.isEmpty else {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = try JSONEncoder().encode(secret)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func secretNames() -> [String] {
        var q = baseQuery(nil)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }
}
#endif
