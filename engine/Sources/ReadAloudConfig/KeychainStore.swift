import Foundation
import Security

private let readAloudKeychainServiceV4 = "com.wentuo.readaloud.volcengine.v4"
private let readAloudKeychainServiceV3 = "com.wentuo.readaloud.volcengine.v3"
private let legacyReadAloudKeychainService = "com.wentuo.readaloud.volcengine"
private let readAloudKeychainAccount = "default"

enum KeychainError: LocalizedError {
    case itemNotFound
    case legacyItemUnavailable
    case accessDenied
    case invalidData
    case emptyValue
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "未配置 API Key，请打开设置后输入并保存"
        case .legacyItemUnavailable:
            return "旧版 API Key 无法迁移，请打开设置后重新输入并保存一次"
        case .accessDenied:
            return "暂时无法访问已保存的 API Key，请重新打开 Omi 后再试；仍失败请在设置中重新输入并保存"
        case .invalidData:
            return "API Key 读取失败，请重新配置"
        case .emptyValue:
            return "API Key 为空，请重新配置"
        case .unexpectedStatus(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "无法读取 API Key（\(status)：\(detail)）"
        }
    }
}

struct KeychainStore {
    private let service: String
    private let usesDataProtectionKeychain: Bool
    private let migratesLegacyItem: Bool

    init(
        service: String = readAloudKeychainServiceV4,
        usesDataProtectionKeychain: Bool = false,
        migratesLegacyItem: Bool = true
    ) {
        self.service = service
        self.usesDataProtectionKeychain = usesDataProtectionKeychain
        self.migratesLegacyItem = migratesLegacyItem
    }

    func save(_ rawValue: String) throws {
        let value = normalized(rawValue)
        guard !value.isEmpty else { throw KeychainError.emptyValue }
        let data = Data(value.utf8)
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            if usesDataProtectionKeychain {
                addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw keychainError(for: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw keychainError(for: updateStatus)
        }
    }

    func exists() -> Bool {
        var query = baseQuery()
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func read() throws -> String {
        do {
            return try readStoredValue()
        } catch KeychainError.itemNotFound where migratesLegacyItem {
            return try migrateLegacyValue()
        }
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(for: status)
        }
    }

    private func migrateLegacyValue() throws -> String {
        for legacyService in [readAloudKeychainServiceV3, legacyReadAloudKeychainService] {
            let legacyStore = KeychainStore(
                service: legacyService,
                usesDataProtectionKeychain: false,
                migratesLegacyItem: false
            )
            do {
                let value = try legacyStore.readStoredValue()
                try save(value)
                return value
            } catch KeychainError.itemNotFound {
                continue
            } catch KeychainError.accessDenied {
                throw KeychainError.legacyItemUnavailable
            }
        }
        throw KeychainError.itemNotFound
    }

    private func readStoredValue() throws -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            throw KeychainError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw keychainError(for: status)
        }
        guard let result else {
            throw KeychainError.invalidData
        }

        let data: Data
        if let value = result as? Data {
            data = value
        } else if let value = result as? NSData {
            data = Data(referencing: value)
        } else {
            throw KeychainError.invalidData
        }

        guard let rawValue = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        let value = normalized(rawValue)
        guard !value.isEmpty else {
            throw KeychainError.emptyValue
        }
        return value
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: readAloudKeychainAccount
        ]
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private func keychainError(for status: OSStatus) -> KeychainError {
        status == errSecAuthFailed
            ? .accessDenied
            : .unexpectedStatus(status)
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
