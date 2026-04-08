import Foundation
import CryptoKit

/// Stores session data in AES-256-GCM encrypted files in Application Support.
enum KeychainHelper {
    private static var storageDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/steamguard-cli/sessions"
    }

    private static func ensureDir() {
        try? FileManager.default.createDirectory(atPath: storageDir, withIntermediateDirectories: true)
    }

    private static func filePath(for account: String, suffix: String = "session") -> String {
        let safe = account.replacingOccurrences(of: "/", with: "_")
        return "\(storageDir)/\(safe).\(suffix)"
    }

    /// Returns the encryption key, generating and persisting a random one on first use.
    /// The key file is protected with 0600 permissions (owner-only).
    private static var encryptionKey: SymmetricKey {
        let keyPath = "\(storageDir)/.sma_key"
        ensureDir()

        // Try to load existing key
        if let keyData = try? Data(contentsOf: URL(fileURLWithPath: keyPath)),
           keyData.count == 32 {
            return SymmetricKey(data: keyData)
        }

        // Generate a new random 256-bit key
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        let keyData = Data(keyBytes)

        // Save with owner-only permissions
        FileManager.default.createFile(atPath: keyPath, contents: keyData, attributes: [.posixPermissions: 0o600])

        return SymmetricKey(data: keyData)
    }

    // MARK: - Encrypt / Decrypt helpers

    /// Set file permissions to owner-only (0600)
    private static func restrictPermissions(_ path: String) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    private static func encryptAndSave(_ data: Data, to path: String) {
        do {
            let sealed = try AES.GCM.seal(data, using: encryptionKey)
            guard let combined = sealed.combined else { return }
            try combined.write(to: URL(fileURLWithPath: path))
            restrictPermissions(path)
        } catch {
            #if DEBUG
            print("[KeychainHelper] encryptAndSave failed: \(error)")
            #endif
        }
    }

    private static func loadAndDecrypt(from path: String) -> Data? {
        guard FileManager.default.fileExists(atPath: path),
              let combined = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: encryptionKey)
        } catch {
            return nil
        }
    }

    // MARK: - Session cookies

    static func saveSession(accountName: String, cookies: [HTTPCookie]) {
        ensureDir()
        let cookieData = cookies.compactMap { cookie -> [String: String]? in
            return [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path
            ]
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: cookieData) else { return }
        encryptAndSave(jsonData, to: filePath(for: accountName))
    }

    static func loadSession(accountName: String) -> [HTTPCookie]? {
        guard let jsonData = loadAndDecrypt(from: filePath(for: accountName)),
              let cookieArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] else {
            return nil
        }

        let cookies = cookieArray.compactMap { dict -> HTTPCookie? in
            guard let name = dict["name"],
                  let value = dict["value"],
                  let domain = dict["domain"],
                  let path = dict["path"] else { return nil }
            return HTTPCookie(properties: [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path,
                .secure: "TRUE",
                .expires: Date.distantFuture
            ])
        }
        return cookies.isEmpty ? nil : cookies
    }

    /// Update a specific cookie value in the stored session
    static func updateCookieValue(accountName: String, cookieName: String, newValue: String) {
        guard let jsonData = loadAndDecrypt(from: filePath(for: accountName)),
              var cookieArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] else { return }

        for i in 0..<cookieArray.count {
            if cookieArray[i]["name"] == cookieName {
                cookieArray[i]["value"] = newValue
            }
        }

        guard let updatedData = try? JSONSerialization.data(withJSONObject: cookieArray) else { return }
        encryptAndSave(updatedData, to: filePath(for: accountName))
    }

    static func hasSession(accountName: String) -> Bool {
        return FileManager.default.fileExists(atPath: filePath(for: accountName))
    }

    static func deleteSession(accountName: String) {
        try? FileManager.default.removeItem(atPath: filePath(for: accountName))
        try? FileManager.default.removeItem(atPath: filePath(for: accountName, suffix: "refresh"))
    }

    // MARK: - Refresh token (stored separately, lasts ~200 days)

    static func saveRefreshToken(accountName: String, token: String) {
        ensureDir()
        guard let data = token.data(using: .utf8) else { return }
        encryptAndSave(data, to: filePath(for: accountName, suffix: "refresh"))
    }

    static func loadRefreshToken(accountName: String) -> String? {
        guard let data = loadAndDecrypt(from: filePath(for: accountName, suffix: "refresh")) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
