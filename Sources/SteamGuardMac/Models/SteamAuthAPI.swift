import Foundation
import Security

enum AuthError: LocalizedError {
    case rsaKeyFailed
    case encryptionFailed
    case loginFailed(String)
    case needsEmailCode
    case needsDeviceConfirmation
    case needsTwoFactorCode
    case phoneFailed(String)
    case authenticatorFailed(String)
    case finalizeFailed(String)
    case invalidSMSCode
    case alreadyHasAuthenticator
    case noPhoneOnAccount
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .rsaKeyFailed: return "Failed to get RSA key from Steam."
        case .encryptionFailed: return "Failed to encrypt password."
        case .loginFailed(let msg): return "Login failed: \(msg)"
        case .needsEmailCode: return "Email code required."
        case .needsDeviceConfirmation: return "Device confirmation required."
        case .needsTwoFactorCode: return "Two-factor code required."
        case .phoneFailed(let msg): return "Phone setup failed: \(msg)"
        case .authenticatorFailed(let msg): return "Authenticator setup failed: \(msg)"
        case .finalizeFailed(let msg): return "Finalization failed: \(msg)"
        case .invalidSMSCode: return "Invalid SMS code. Please try again."
        case .alreadyHasAuthenticator: return "This account already has an authenticator. Remove it first in Steam settings."
        case .noPhoneOnAccount: return "No phone number on this account."
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}

struct AuthSession {
    let clientId: UInt64
    let requestId: Data
    let steamId: UInt64
    let interval: Double
    let allowedConfirmations: [Int]
}

struct LoginResult {
    let accessToken: String
    let refreshToken: String
    let steamId: UInt64
    let accountName: String
}

struct NewAuthenticator {
    let sharedSecret: String
    let identitySecret: String
    let revocationCode: String
    let serialNumber: String
    let accountName: String
    let tokenGid: String
    let secret1: String
    let uri: String
    let deviceId: String
    let steamId: UInt64
    let serverTime: UInt64
}

/// Steam Web API client for authentication, phone verification, and authenticator management.
enum SteamAuthAPI {
    private static let apiBase = "https://api.steampowered.com"

    // MARK: - Helpers

    private static func post(_ endpoint: String, params: [String: String], accessToken: String? = nil) async throws -> [String: Any] {
        let urlString = "\(apiBase)\(endpoint)"
        guard let url = URL(string: urlString) else { throw AuthError.networkError("Invalid URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Pass access token in POST body, not URL query (security best practice)
        var allParams = params
        if let token = accessToken {
            allParams["access_token"] = token
        }

        // Must use a strict character set — base64 contains +/= which break form encoding
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = allParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.networkError("HTTP \(httpResponse.statusCode): \(bodyStr.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.networkError("Invalid response")
        }
        return json
    }

    // MARK: - RSA Key & Password Encryption

    static func getPasswordRSAPublicKey(accountName: String) async throws -> (modulus: String, exponent: String, timestamp: String) {
        let encoded = accountName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? accountName
        let url = URL(string: "\(apiBase)/IAuthenticationService/GetPasswordRSAPublicKey/v1/?account_name=\(encoded)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.rsaKeyFailed
        }
        guard let response = json["response"] as? [String: Any],
              let modulus = response["publickey_mod"] as? String,
              let exponent = response["publickey_exp"] as? String,
              let timestamp = response["timestamp"] as? String else {
            throw AuthError.rsaKeyFailed
        }
        return (modulus, exponent, timestamp)
    }

    static func encryptPassword(_ password: String, modulus: String, exponent: String) throws -> String {
        guard let modulusData = hexToData(modulus),
              let exponentData = hexToData(exponent),
              let passwordData = password.data(using: .utf8) else {
            throw AuthError.encryptionFailed
        }

        let derKey = buildPKCS1PublicKey(modulus: modulusData, exponent: exponentData)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: modulusData.count * 8
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(derKey as CFData, attributes as CFDictionary, &error) else {
            throw AuthError.encryptionFailed
        }
        guard let encrypted = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, passwordData as CFData, &error) else {
            throw AuthError.encryptionFailed
        }
        return (encrypted as Data).base64EncodedString()
    }

    // MARK: - Login

    static func beginAuthSession(accountName: String, encryptedPassword: String, timestamp: String) async throws -> AuthSession {
        let params: [String: String] = [
            "account_name": accountName,
            "encrypted_password": encryptedPassword,
            "encryption_timestamp": timestamp,
            "device_friendly_name": "SMA",
            "platform_type": "2",  // mobile
            "persistence": "1",
            "website_id": "Mobile"
        ]

        let json = try await post("/IAuthenticationService/BeginAuthSessionViaCredentials/v1/", params: params)
        guard let response = json["response"] as? [String: Any] else {
            throw AuthError.loginFailed("No response from Steam")
        }

        // Check for error message
        let extError = response["extended_error_message"] as? String ?? ""

        // client_id can be String or Number
        let clientId: UInt64
        if let n = response["client_id"] as? UInt64 { clientId = n }
        else if let n = response["client_id"] as? Int { clientId = UInt64(n) }
        else if let s = response["client_id"] as? String, let n = UInt64(s) { clientId = n }
        else {
            throw AuthError.loginFailed(extError.isEmpty ? "Invalid username or password." : extError)
        }

        // request_id is base64
        guard let reqIdStr = response["request_id"] as? String,
              let requestId = Data(base64Encoded: reqIdStr) else {
            throw AuthError.loginFailed("Missing request_id")
        }

        let steamId: UInt64
        if let n = response["steamid"] as? UInt64 { steamId = n }
        else if let n = response["steamid"] as? Int { steamId = UInt64(n) }
        else if let s = response["steamid"] as? String, let n = UInt64(s) { steamId = n }
        else { steamId = 0 }

        let interval = (response["interval"] as? Double) ?? 5.0

        var confirmations: [Int] = []
        if let confs = response["allowed_confirmations"] as? [[String: Any]] {
            for conf in confs {
                if let type = conf["confirmation_type"] as? Int { confirmations.append(type) }
                else if let type = conf["confirmation_type"] as? String, let t = Int(type) { confirmations.append(t) }
            }
        }

        return AuthSession(clientId: clientId, requestId: requestId, steamId: steamId, interval: interval, allowedConfirmations: confirmations)
    }

    static func submitSteamGuardCode(clientId: UInt64, steamId: UInt64, code: String, codeType: Int) async throws {
        let params: [String: String] = [
            "client_id": String(clientId),
            "steamid": String(steamId),
            "code": code,
            "code_type": String(codeType)  // 2 = email, 5 = totp
        ]

        // This endpoint returns HTTP 429 for wrong code, or error in EResult
        do {
            let json = try await post("/IAuthenticationService/UpdateAuthSessionWithSteamGuardCode/v1/", params: params)

            if let response = json["response"] as? [String: Any],
               let errMsg = response["extended_error_message"] as? String, !errMsg.isEmpty {
                throw AuthError.loginFailed(errMsg)
            }
        } catch AuthError.networkError(let msg) {
            if msg.contains("429") {
                throw AuthError.loginFailed("Too many attempts. Wait a few minutes and try again.")
            } else if msg.contains("400") {
                throw AuthError.loginFailed("Invalid code. Please check and try again.")
            }
            throw AuthError.networkError(msg)
        }
    }

    static func pollAuthSession(clientId: UInt64, requestId: Data) async throws -> LoginResult? {
        let params: [String: String] = [
            "client_id": String(clientId),
            "request_id": requestId.base64EncodedString()
        ]

        let json: [String: Any]
        do {
            json = try await post("/IAuthenticationService/PollAuthSessionStatus/v1/", params: params)
        } catch {
            // Network errors during polling are non-fatal, just retry
            return nil
        }

        guard let response = json["response"] as? [String: Any] else { return nil }

        // Check for access_token or refresh_token
        let accessToken = response["access_token"] as? String ?? ""
        let refreshToken = response["refresh_token"] as? String ?? ""

        // If both are empty, Steam hasn't processed the auth yet
        if accessToken.isEmpty && refreshToken.isEmpty {
            return nil
        }

        let accountName = response["account_name"] as? String ?? ""

        // Extract steamid from access token JWT
        var steamId: UInt64 = 0
        if !accessToken.isEmpty,
           let payload = TokenRefresher.decodeJWTPayload(accessToken),
           let sub = payload["sub"] as? String, let sid = UInt64(sub) {
            steamId = sid
        }

        return LoginResult(accessToken: accessToken, refreshToken: refreshToken, steamId: steamId, accountName: accountName)
    }

    // MARK: - Phone

    static func checkPhoneStatus(accessToken: String) async throws -> Bool {
        let statusJson = try await post("/IPhoneService/AccountPhoneStatus/v1/", params: [:], accessToken: accessToken)
        if let response = statusJson["response"] as? [String: Any] {
            if let hasPhone = response["has_confirmed_phone"] as? Bool { return hasPhone }
            if let hasPhone = response["has_confirmed_phone"] as? Int { return hasPhone != 0 }
            // Some responses use different field names
            if let state = response["state"] as? Int { return state > 0 }
        }
        return false
    }

    static func setPhoneNumber(accessToken: String, phoneNumber: String, countryCode: String) async throws {
        let params: [String: String] = [
            "phone_number": phoneNumber,
            "phone_country_code": countryCode
        ]
        let json = try await post("/IPhoneService/SetAccountPhoneNumber/v1/", params: params, accessToken: accessToken)
        if let response = json["response"] as? [String: Any],
           response["confirmation_email_address"] != nil {
            // Email sent, waiting for confirmation
            return
        }
    }

    static func isWaitingForEmailConfirmation(accessToken: String) async throws -> Bool {
        let json = try await post("/IPhoneService/IsAccountWaitingForEmailConfirmation/v1/", params: [:], accessToken: accessToken)
        if let response = json["response"] as? [String: Any],
           let waiting = response["awaiting_email_confirmation"] as? Bool {
            return waiting
        }
        return false
    }

    static func sendPhoneVerificationCode(accessToken: String) async throws {
        let _ = try await post("/IPhoneService/SendPhoneVerificationCode/v1/", params: [:], accessToken: accessToken)
    }

    static func verifyPhoneWithCode(accessToken: String, code: String) async throws -> Bool {
        let json = try await post("/IPhoneService/VerifyAccountPhoneWithCode/v1/", params: ["code": code], accessToken: accessToken)
        if let response = json["response"] as? [String: Any],
           let success = response["success"] as? Bool {
            return success
        }
        return false
    }

    // MARK: - Authenticator

    static func addAuthenticator(accessToken: String, steamId: UInt64, deviceId: String) async throws -> NewAuthenticator {
        let params: [String: String] = [
            "steamid": String(steamId),
            "authenticator_type": "1",
            "device_identifier": deviceId,
            "sms_phone_id": "1",
            "version": "2"
        ]
        let json = try await post("/ITwoFactorService/AddAuthenticator/v1/", params: params, accessToken: accessToken)
        guard let response = json["response"] as? [String: Any] else {
            throw AuthError.authenticatorFailed("No response from Steam")
        }

        // Check status
        if let status = response["status"] as? Int {
            if status == 29 { throw AuthError.alreadyHasAuthenticator }
            if status == 2 { throw AuthError.noPhoneOnAccount }
            if status != 1 { throw AuthError.authenticatorFailed("Status: \(status)") }
        }

        guard let sharedSecret = response["shared_secret"] as? String,
              let identitySecret = response["identity_secret"] as? String,
              let revocationCode = response["revocation_code"] as? String else {
            throw AuthError.authenticatorFailed("Missing secrets in response")
        }

        let accountName = response["account_name"] as? String ?? ""

        let serverTime: UInt64
        if let t = response["server_time"] as? UInt64 { serverTime = t }
        else if let s = response["server_time"] as? String, let t = UInt64(s) { serverTime = t }
        else { serverTime = UInt64(Date().timeIntervalSince1970) }

        return NewAuthenticator(
            sharedSecret: sharedSecret,
            identitySecret: identitySecret,
            revocationCode: revocationCode,
            serialNumber: response["serial_number"] as? String ?? "",
            accountName: accountName,
            tokenGid: response["token_gid"] as? String ?? "",
            secret1: response["secret_1"] as? String ?? "",
            uri: response["uri"] as? String ?? "",
            deviceId: deviceId,
            steamId: steamId,
            serverTime: serverTime
        )
    }

    static func finalizeAuthenticator(accessToken: String, steamId: UInt64, activationCode: String, authenticatorCode: String, authenticatorTime: UInt64) async throws {
        let params: [String: String] = [
            "steamid": String(steamId),
            "activation_code": activationCode,
            "authenticator_code": authenticatorCode,
            "authenticator_time": String(authenticatorTime),
            "validate_sms_code": "1"
        ]

        // Retry up to 10 times for status 88
        for attempt in 0..<10 {
            let json = try await post("/ITwoFactorService/FinalizeAddAuthenticator/v1/", params: params, accessToken: accessToken)
            guard let response = json["response"] as? [String: Any] else {
                throw AuthError.finalizeFailed("No response")
            }

            if let success = response["success"] as? Bool, success {
                return // Done!
            }

            let status = response["status"] as? Int ?? -1
            if status == 89 { throw AuthError.invalidSMSCode }
            if status == 88 {
                // Retry
                try await Task.sleep(nanoseconds: UInt64(500_000_000))
                continue
            }

            if attempt == 9 {
                throw AuthError.finalizeFailed("Failed after 10 attempts (status: \(status))")
            }
        }
    }

    // MARK: - Remove Authenticator

    static func removeAuthenticator(accessToken: String, steamId: UInt64, revocationCode: String) async throws -> Bool {
        let params: [String: String] = [
            "steamid": String(steamId),
            "revocation_code": revocationCode,
            "steamguard_scheme": "1"
        ]
        let json = try await post("/ITwoFactorService/RemoveAuthenticator/v1/", params: params, accessToken: accessToken)
        if let response = json["response"] as? [String: Any],
           let success = response["success"] as? Bool {
            return success
        }
        return false
    }

    // MARK: - DER / RSA Helpers

    private static func hexToData(_ hex: String) -> Data? {
        var data = Data()
        var temp = hex
        while temp.count >= 2 {
            let byte = String(temp.prefix(2))
            temp = String(temp.dropFirst(2))
            guard let b = UInt8(byte, radix: 16) else { return nil }
            data.append(b)
        }
        return data
    }

    private static func buildPKCS1PublicKey(modulus: Data, exponent: Data) -> Data {
        // PKCS#1 RSAPublicKey ::= SEQUENCE { modulus INTEGER, exponent INTEGER }
        let modInteger = derInteger(modulus)
        let expInteger = derInteger(exponent)
        return derSequence(modInteger + expInteger)
    }

    private static func derInteger(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        // Ensure positive (prepend 0x00 if high bit set)
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0x00, at: 0)
        }
        // Remove leading zeros (keep at least one)
        while bytes.count > 1 && bytes[0] == 0 && bytes[1] & 0x80 == 0 {
            bytes.removeFirst()
        }
        var result = Data([0x02]) // INTEGER tag
        result.append(contentsOf: derLength(bytes.count))
        result.append(contentsOf: bytes)
        return result
    }

    private static func derSequence(_ content: Data) -> Data {
        var result = Data([0x30]) // SEQUENCE tag
        result.append(contentsOf: derLength(content.count))
        result.append(content)
        return result
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 128 {
            return Data([UInt8(length)])
        } else if length < 256 {
            return Data([0x81, UInt8(length)])
        } else {
            return Data([0x82, UInt8(length >> 8), UInt8(length & 0xFF)])
        }
    }
}
