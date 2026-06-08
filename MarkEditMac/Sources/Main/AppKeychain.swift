//
//  AppKeychain.swift
//  MarkEditMac
//
//  Minimal Keychain wrapper for storing API keys. We use the Generic Password
//  class with a fixed service identifier so multiple keys can coexist by `account`.
//

import Foundation
import MarkEditKit
import Security

enum AppKeychain {
  private static let service = "app.markedit.secrets"

  static func setString(_ value: String?, account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    // Always delete first; then add if non-empty.
    SecItemDelete(query as CFDictionary)

    guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
      return
    }

    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

    let status = SecItemAdd(attributes as CFDictionary, nil)
    if status != errSecSuccess {
      Logger.log(.error, "Keychain SecItemAdd failed (status: \(status)) for account \(account)")
    }
  }

  static func getString(account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }
}
