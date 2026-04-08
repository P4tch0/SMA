import Foundation
import CryptoKit

/// Stores session data in AES-256-GCM encrypted files in Application Support.
/// Per-account folder structure: sessions/{accountName}/session.enc
/// Shared encryption key at: sessions/.sma_key
enum KeychainHelper {
    private static var storageDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/steamguard-cli/sessions"
    }

    private static func ensureDir() {
        try? FileManager.default.createDirectory(atPath: storageDir, withIntermediateDirectories: true)
    }

    /// Returns (and creates if needed) the per-account directory.
    private static func accountDir(for accountName: String) -> String {
        let safe = accountName.replacingOccurrences(of: "/", with: "_")
        let dir = "\(storageDir)/\(safe)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Path to the encrypted session file for an account.
    private static func sessionPath(for accountName: String) -> String {
        return "\(accountDir(for: accountName))/session.enc"
    }

    /// Migrate old-style flat file ({accountName}.session) to per-account folder if needed.
    private static func migrateIfNeeded(for accountName: String) {
        let safe = accountName.replacingOccurrences(of: "/", with: "_")
        let oldPath = "\(storageDir)/\(safe).session"
        let newPath = sessionPath(for: accountName)

        if FileManager.default.fileExists(atPath: oldPath) && !FileManager.default.fileExists(atPath: newPath) {
            try? FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
            // Also clean up old refresh token file if present
            let oldRefresh = "\(storageDir)/\(safe).refresh"
            try? FileManager.default.removeItem(atPath: oldRefresh)
        }
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
        let cookieData = cookies.compactMap { cookie -> [String: String]? in
            return [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path
            ]
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: cookieData) else { return }
        encryptAndSave(jsonData, to: sessionPath(for: accountName))
    }

    static func loadSession(accountName: String) -> [HTTPCookie]? {
        migrateIfNeeded(for: accountName)

        guard let jsonData = loadAndDecrypt(from: sessionPath(for: accountName)),
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

    static func hasSession(accountName: String) -> Bool {
        migrateIfNeeded(for: accountName)
        return FileManager.default.fileExists(atPath: sessionPath(for: accountName))
    }

    static func deleteSession(accountName: String) {
        let dir = accountDir(for: accountName)
        try? FileManager.default.removeItem(atPath: "\(dir)/session.enc")
        // Also clean up old-style files if they exist
        let safe = accountName.replacingOccurrences(of: "/", with: "_")
        try? FileManager.default.removeItem(atPath: "\(storageDir)/\(safe).session")
        try? FileManager.default.removeItem(atPath: "\(storageDir)/\(safe).refresh")
    }

    /// Create the per-account session folder (e.g. on import, before any login).
    static func ensureAccountDir(for accountName: String) {
        _ = accountDir(for: accountName)
    }
}
