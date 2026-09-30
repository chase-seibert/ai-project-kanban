import Foundation
import Security

/// Small Keychain wrapper for pairing secrets and device-scoped sync keys.
public enum KeychainVault {
  public static func read(service: String, account: String) throws -> Data? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    #if os(iOS)
      query[kSecAttrSynchronizable as String] = false
    #endif
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw BoardError.invalid("Could not read StageChase pairing data from Keychain (\(status)).")
    }
    return result as? Data
  }

  public static func save(_ data: Data, service: String, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let update: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var insert = query
      for (key, value) in update {
        insert[key] = value
      }
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(insert as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw BoardError.invalid(
          "Could not save StageChase pairing data to Keychain (\(addStatus)).")
      }
    } else if status != errSecSuccess {
      throw BoardError.invalid("Could not update StageChase pairing data (\(status)).")
    }
  }

  public static func delete(service: String, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw BoardError.invalid("Could not remove StageChase pairing data (\(status)).")
    }
  }
}
