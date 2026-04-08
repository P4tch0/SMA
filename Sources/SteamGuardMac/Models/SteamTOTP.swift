import Foundation
import CommonCrypto

/// Steam Guard TOTP code generation, confirmation hashing, and server time synchronization.
enum SteamTOTP {
    private static let steamChars = Array("23456789BCDFGHJKMNPQRTVWXY")

    /// Offset between local time and Steam server time (in seconds).
    /// Access synchronized via lock to prevent race conditions between sync and code generation.
    private static let lock = NSLock()
    private static var _timeOffset: Int64 = 0
    private static var _lastSyncDate: Date?

    private static var timeOffset: Int64 {
        get { lock.lock(); defer { lock.unlock() }; return _timeOffset }
        set { lock.lock(); defer { lock.unlock() }; _timeOffset = newValue }
    }
    private static var lastSyncDate: Date? {
        get { lock.lock(); defer { lock.unlock() }; return _lastSyncDate }
        set { lock.lock(); defer { lock.unlock() }; _lastSyncDate = newValue }
    }

    /// Current time aligned with Steam servers
    static var serverTime: UInt64 {
        UInt64(max(0, Int64(Date().timeIntervalSince1970) + timeOffset))
    }

    /// Whether time has been synced recently (within last 10 minutes)
    static var isSynced: Bool {
        guard let last = lastSyncDate else { return false }
        return Date().timeIntervalSince(last) < 600
    }

    /// Sync local clock with Steam's server time.
    /// Accounts for network round-trip latency.
    static func syncTime() async {
        guard let url = URL(string: "https://api.steampowered.com/ITwoFactorService/QueryTime/v1/") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()

        let startTime = Date()

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let networkLatency = Date().timeIntervalSince(startTime)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let response = json["response"] as? [String: Any] {
                let steamTime: Int64
                if let t = response["server_time"] as? Int64 {
                    steamTime = t
                } else if let s = response["server_time"] as? String, let t = Int64(s) {
                    steamTime = t
                } else {
                    return
                }
                // Adjust for half the round-trip (server time was generated mid-request)
                let adjustedSteamTime = steamTime + Int64(networkLatency / 2)
                timeOffset = adjustedSteamTime - Int64(Date().timeIntervalSince1970)
                lastSyncDate = Date()
            }
        } catch {
            #if DEBUG
            print("[SteamTOTP] syncTime failed: \(error)")
            #endif
        }
    }

    /// Ensure time is synced before generating confirmation hashes.
    /// Re-syncs if stale (>10 min) or never synced.
    static func ensureSynced() async {
        if !isSynced {
            await syncTime()
        }
    }

    static func generateCode(sharedSecret: String) -> String {
        guard let secretData = Data(base64Encoded: sharedSecret) else { return "ERROR" }

        let time = serverTime / 30
        var timeBytes = Data(count: 8)
        for i in 0..<8 {
            timeBytes[7 - i] = UInt8(truncatingIfNeeded: time >> (i * 8))
        }

        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        timeBytes.withUnsafeBytes { timePtr in
            secretData.withUnsafeBytes { secretPtr in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA1),
                    secretPtr.baseAddress, secretData.count,
                    timePtr.baseAddress, timeBytes.count,
                    &hmac
                )
            }
        }

        let offset = Int(hmac[19] & 0x0f)
        var code: UInt32 = UInt32(hmac[offset] & 0x7f) << 24
        code |= UInt32(hmac[offset + 1]) << 16
        code |= UInt32(hmac[offset + 2]) << 8
        code |= UInt32(hmac[offset + 3])

        var result = ""
        var fullCode = code
        for _ in 0..<5 {
            result.append(steamChars[Int(fullCode) % steamChars.count])
            fullCode /= UInt32(steamChars.count)
        }

        return result
    }

    /// Returns seconds remaining until the current code expires (0-30)
    static func secondsRemaining() -> Int {
        30 - Int(Double(serverTime).truncatingRemainder(dividingBy: 30))
    }

    /// Generate confirmation hash for trade confirmations
    static func generateConfirmationHash(identitySecret: String, time: UInt64, tag: String) -> String? {
        guard let secretData = Data(base64Encoded: identitySecret) else { return nil }

        let tagBytes = Array(tag.utf8)
        var dataToHash = Data(count: 8 + min(tagBytes.count, 32))
        for i in 0..<8 {
            dataToHash[7 - i] = UInt8(truncatingIfNeeded: time >> (i * 8))
        }
        for i in 0..<min(tagBytes.count, 32) {
            dataToHash[8 + i] = tagBytes[i]
        }

        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        dataToHash.withUnsafeBytes { dataPtr in
            secretData.withUnsafeBytes { secretPtr in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA1),
                    secretPtr.baseAddress, secretData.count,
                    dataPtr.baseAddress, dataToHash.count,
                    &hmac
                )
            }
        }

        return Data(hmac).base64EncodedString()
    }
}
