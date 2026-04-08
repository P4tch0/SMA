import Foundation
import CommonCrypto

/// Decrypts SDA-encrypted maFiles using PBKDF2 + AES-256-CBC.
/// SDA stores encryption_iv and encryption_salt in manifest.json per entry.
enum SDADecryptor {

    struct ManifestEntry {
        let filename: String
        let iv: Data     // base64-decoded encryption_iv
        let salt: Data   // base64-decoded encryption_salt
    }

    /// Check if data looks encrypted (not valid JSON, likely base64)
    static func isEncrypted(_ data: Data) -> Bool {
        // If it parses as JSON, it's not encrypted
        if (try? JSONSerialization.jsonObject(with: data)) != nil { return false }
        // If it's valid UTF-8 text that looks like base64
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           Data(base64Encoded: text) != nil {
            return true
        }
        return false
    }

    /// Try to find and parse an SDA manifest.json in the same directory as the file.
    /// Uses direct file path access (not URL-scoped) since the app is not sandboxed.
    static func findManifest(near fileURL: URL) -> [ManifestEntry]? {
        let dir = fileURL.deletingLastPathComponent().path
        let manifestPath = (dir as NSString).appendingPathComponent("manifest.json")

        guard FileManager.default.fileExists(atPath: manifestPath),
              let data = FileManager.default.contents(atPath: manifestPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]] else {
            return nil
        }

        return entries.compactMap { entry -> ManifestEntry? in
            guard let filename = entry["filename"] as? String,
                  let ivB64 = entry["encryption_iv"] as? String,
                  let saltB64 = entry["encryption_salt"] as? String,
                  let iv = Data(base64Encoded: ivB64),
                  let salt = Data(base64Encoded: saltB64) else { return nil }
            return ManifestEntry(filename: filename, iv: iv, salt: salt)
        }
    }

    /// Decrypt an SDA-encrypted maFile
    /// - Parameters:
    ///   - encryptedData: The raw file data (base64-encoded ciphertext)
    ///   - password: The SDA encryption passkey
    ///   - iv: From manifest entry encryption_iv
    ///   - salt: From manifest entry encryption_salt
    /// - Returns: Decrypted JSON data, or nil if decryption fails
    static func decrypt(encryptedData: Data, password: String, iv: Data, salt: Data) -> Data? {
        // Decode base64
        guard let text = String(data: encryptedData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let ciphertext = Data(base64Encoded: text) else { return nil }

        // Derive key: PBKDF2-SHA1, 50000 iterations, 32-byte key
        guard let passwordData = password.data(using: .utf8) else { return nil }

        var derivedKey = [UInt8](repeating: 0, count: 32)
        let status = passwordData.withUnsafeBytes { pwBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                    passwordData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    50000,
                    &derivedKey,
                    32
                )
            }
        }
        guard status == kCCSuccess else { return nil }

        // Decrypt: AES-256-CBC with PKCS7 padding
        let bufferSize = ciphertext.count + kCCBlockSizeAES128
        var decrypted = [UInt8](repeating: 0, count: bufferSize)
        var decryptedLength = 0

        let cryptStatus = derivedKey.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                ciphertext.withUnsafeBytes { cipherBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, 32,
                        ivBytes.baseAddress,
                        cipherBytes.baseAddress, ciphertext.count,
                        &decrypted, bufferSize,
                        &decryptedLength
                    )
                }
            }
        }

        guard cryptStatus == kCCSuccess, decryptedLength > 0 else { return nil }

        let result = Data(decrypted.prefix(decryptedLength))

        // Verify it's valid JSON
        guard (try? JSONSerialization.jsonObject(with: result)) != nil else { return nil }

        return result
    }
}
