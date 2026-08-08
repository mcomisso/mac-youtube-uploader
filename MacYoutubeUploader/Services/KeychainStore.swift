import Foundation
@preconcurrency import KeychainAccess

enum KeychainStore {
    static func save(_ data: Data, service: String, account: String) throws {
        try keychain(service: service).set(data, key: account)
    }

    static func load(service: String, account: String) throws -> Data? {
        try keychain(service: service).getData(account)
    }

    static func saveString(_ value: String, service: String, account: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try delete(service: service, account: account)
        } else {
            try keychain(service: service).set(value, key: account)
        }
    }

    static func loadString(service: String, account: String) throws -> String? {
        try keychain(service: service).get(account)
    }

    static func delete(service: String, account: String) throws {
        try keychain(service: service).remove(account)
    }

    private static func keychain(service: String) -> Keychain {
        Keychain(service: service)
            .accessibility(.afterFirstUnlock)
    }
}
