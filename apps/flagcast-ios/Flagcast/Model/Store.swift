import Foundation
import Security

/// Small things kept on this phone (UserDefaults, as JSON).
enum Store {
    static func get<T: Decodable>(_ key: String, _ fallback: T) -> T {
        guard let d = UserDefaults.standard.data(forKey: key), let v = try? JSONDecoder().decode(T.self, from: d) else { return fallback }
        return v
    }
    static func set<T: Encodable>(_ key: String, _ value: T) {
        if let d = try? JSONEncoder().encode(value) { UserDefaults.standard.set(d, forKey: key) }
    }
    static func remove(_ key: String) { UserDefaults.standard.removeObject(forKey: key) }
}

/// Where this phone has played, newest first, so the home screen can go straight back in.
struct Recent: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var code: String
    var at: Double
}

enum Recents {
    static let key = "flagcast.recent"
    static func all() -> [Recent] { Store.get(key, [Recent]()) }
    static func remember(id: String, name: String, code: String = "") {
        var list = all()
        let prev = list.first { $0.id == id }
        list.removeAll { $0.id == id }
        list.insert(Recent(id: id, name: name.isEmpty ? (prev?.name ?? "Tournament") : name, code: code.isEmpty ? (prev?.code ?? "") : code,
                           at: Date().timeIntervalSince1970 * 1000), at: 0)
        Store.set(key, Array(list.prefix(10)))
    }
    static func forget(_ id: String) {
        Store.set(key, all().filter { $0.id != id })
    }
}

/// Golf pro and marshal PINs, kept in the Keychain (one per tournament).
enum PinStore {
    private static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.flagcast.golf.pin", kSecAttrAccount as String: id]
    }
    static func save(_ pin: String, for id: String) {
        SecItemDelete(query(id) as CFDictionary)
        var q = query(id)
        q[kSecValueData as String] = Data(pin.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
    static func load(_ id: String) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ id: String) { SecItemDelete(query(id) as CFDictionary) }
}

/// Signed-in pro sessions the home screen lists (the PIN itself stays in the Keychain).
struct ProSignIn: Codable, Hashable, Identifiable {
    var id: String
    var event: String
    var name: String
    var role: String
}
enum ProSignIns {
    static let key = "flagcast.pro"
    static func all() -> [ProSignIn] { Store.get(key, [ProSignIn]()) }
    static func save(_ s: ProSignIn) { Store.set(key, [s] + all().filter { $0.id != s.id }) }
    static func remove(_ id: String) { Store.set(key, all().filter { $0.id != id }); PinStore.delete(id) }
}
