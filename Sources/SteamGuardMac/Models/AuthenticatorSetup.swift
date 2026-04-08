import Foundation

enum SetupStep: Equatable {
    case login
    case phoneSetup
    case phoneEmailConfirmation
    case phoneSMSVerify
    case addingAuthenticator
    case revocationCode
    case finalizeSMS
    case done
}

/// Orchestrates the full Steam Guard authenticator setup flow: login → phone → add → finalize.
@MainActor
class AuthenticatorSetup: ObservableObject {
    @Published var step: SetupStep = .login
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    // Login
    @Published var username = ""
    @Published var loggedIn = false

    // Phone
    @Published var phoneNumber = ""
    @Published var countryCode = "US"
    @Published var phoneSMSCode = ""
    @Published var hasPhone = false

    // Authenticator
    @Published var revocationCode = ""
    @Published var finalizeSMSCode = ""
    @Published var newAuthenticator: NewAuthenticator?

    // Internal — set after WebView login
    private var accessTokenValue: String?
    private var steamId: UInt64 = 0
    private var loginCookies: [HTTPCookie] = []

    var accessToken: String? { accessTokenValue }

    // MARK: - Step 1: Login via WebView cookies

    func handleWebViewLogin(cookies: [HTTPCookie]) async {
        // Extract access token from steamLoginSecure cookie
        guard let loginCookie = cookies.first(where: { $0.name == "steamLoginSecure" && !$0.value.isEmpty }),
              let jwt = TokenRefresher.extractAccessToken(from: loginCookie.value),
              let sid = TokenRefresher.extractSteamID(from: loginCookie.value),
              let sidNum = UInt64(sid) else {
            errorMessage = "Login succeeded but couldn't extract session token. Try again."
            return
        }

        accessTokenValue = jwt
        steamId = sidNum
        loginCookies = cookies

        // Try to get account name from JWT
        if let payload = TokenRefresher.decodeJWTPayload(jwt),
           let sub = payload["sub"] as? String {
            if username.isEmpty { username = sub }
        }

        loggedIn = true

        // Check phone and proceed
        await checkPhoneAndProceed()
    }

    // MARK: - Check Phone

    private func checkPhoneAndProceed() async {
        guard let token = accessToken else { return }

        isWorking = true
        statusMessage = "Checking account status..."

        // First try adding authenticator directly — if the account has a phone,
        // this skips the phone setup entirely. If not, Steam returns status 2 (no phone).
        do {
            hasPhone = try await SteamAuthAPI.checkPhoneStatus(accessToken: token)
        } catch {
            // Phone check failed — try adding authenticator anyway
            // Steam will reject with status 2 if phone is needed
            hasPhone = false
        }

        if hasPhone {
            await addAuthenticator()
        } else {
            // Try addAuthenticator first — maybe the check was wrong
            // If it fails with noPhoneOnAccount, then show phone setup
            await tryAddAuthenticatorOrPhoneSetup()
        }
    }

    private func tryAddAuthenticatorOrPhoneSetup() async {
        guard let token = accessToken, steamId != 0 else { return }

        let deviceId = "android:\(UUID().uuidString.lowercased())"

        do {
            statusMessage = "Adding authenticator..."
            let auth = try await SteamAuthAPI.addAuthenticator(accessToken: token, steamId: steamId, deviceId: deviceId)
            newAuthenticator = auth
            revocationCode = auth.revocationCode
            saveMaFile(auth)

            isWorking = false
            statusMessage = nil
            step = .revocationCode
        } catch AuthError.noPhoneOnAccount {
            // Confirmed — need phone setup
            isWorking = false
            statusMessage = nil
            errorMessage = nil
            step = .phoneSetup
        } catch AuthError.alreadyHasAuthenticator {
            isWorking = false
            errorMessage = "This account already has an authenticator. Remove it in Steam settings first."
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Phone Setup

    func submitPhoneNumber() async {
        guard let token = accessToken, !phoneNumber.isEmpty else {
            errorMessage = "Enter your phone number."
            return
        }

        isWorking = true
        errorMessage = nil

        do {
            statusMessage = "Setting phone number..."
            try await SteamAuthAPI.setPhoneNumber(accessToken: token, phoneNumber: phoneNumber, countryCode: countryCode)

            isWorking = false
            statusMessage = "Check your email — Steam sent a confirmation link."
            step = .phoneEmailConfirmation
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
        }
    }

    func checkEmailConfirmation() async {
        guard let token = accessToken else { return }

        isWorking = true
        errorMessage = nil
        statusMessage = "Checking email confirmation..."

        for _ in 0..<60 {
            do {
                let waiting = try await SteamAuthAPI.isWaitingForEmailConfirmation(accessToken: token)
                if !waiting {
                    // Email confirmed — send SMS
                    statusMessage = "Sending SMS code..."
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Steam rate limit
                    try await SteamAuthAPI.sendPhoneVerificationCode(accessToken: token)

                    isWorking = false
                    statusMessage = nil
                    step = .phoneSMSVerify
                    return
                }
            } catch {
                #if DEBUG
                print("[AuthenticatorSetup] checkEmailConfirmation poll error: \(error)")
                #endif
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }

        isWorking = false
        errorMessage = "Email confirmation timed out."
    }

    func verifyPhoneSMS() async {
        guard let token = accessToken, !phoneSMSCode.isEmpty else {
            errorMessage = "Enter the SMS code."
            return
        }

        isWorking = true
        errorMessage = nil

        do {
            statusMessage = "Verifying phone..."
            let success = try await SteamAuthAPI.verifyPhoneWithCode(accessToken: token, code: phoneSMSCode)

            if success {
                hasPhone = true
                await addAuthenticator()
            } else {
                isWorking = false
                errorMessage = "Invalid SMS code. Try again."
            }
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add Authenticator

    private func addAuthenticator() async {
        guard let token = accessToken, steamId != 0 else { return }

        isWorking = true
        statusMessage = "Adding authenticator..."
        step = .addingAuthenticator

        let deviceId = "android:\(UUID().uuidString.lowercased())"

        do {
            let auth = try await SteamAuthAPI.addAuthenticator(accessToken: token, steamId: steamId, deviceId: deviceId)
            newAuthenticator = auth
            revocationCode = auth.revocationCode

            // IMMEDIATELY save the maFile (crash protection)
            saveMaFile(auth)

            isWorking = false
            statusMessage = nil
            step = .revocationCode
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    // MARK: - Finalize

    func finalizeWithSMS() async {
        guard let token = accessToken,
              steamId != 0,
              let auth = newAuthenticator,
              !finalizeSMSCode.isEmpty else {
            errorMessage = "Enter the SMS code sent to your phone."
            return
        }

        isWorking = true
        errorMessage = nil

        do {
            await SteamTOTP.ensureSynced()
            let time = SteamTOTP.serverTime
            let code = SteamTOTP.generateCode(sharedSecret: auth.sharedSecret)

            statusMessage = "Finalizing..."
            try await SteamAuthAPI.finalizeAuthenticator(
                accessToken: token,
                steamId: steamId,
                activationCode: finalizeSMSCode,
                authenticatorCode: code,
                authenticatorTime: time
            )

            // Update maFile to mark as fully enrolled
            saveMaFile(auth, fullyEnrolled: true)

            // Save to steamguard-cli manifest
            saveToManifest(auth)

            // Save session so user doesn't need to log in again for confirmations
            let accountName = auth.accountName.isEmpty ? username : auth.accountName
            saveSession(accountName: accountName)

            isWorking = false
            statusMessage = nil
            step = .done

        } catch AuthError.invalidSMSCode {
            isWorking = false
            errorMessage = "Invalid SMS code. Check and try again."
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - File Operations

    private func saveSession(accountName: String) {
        guard !loginCookies.isEmpty else { return }

        let relevantCookies = loginCookies.filter {
            ["steamLoginSecure", "sessionid"].contains($0.name) ||
            $0.name.starts(with: "steamMachineAuth")
        }
        KeychainHelper.saveSession(accountName: accountName, cookies: relevantCookies)

        // Save refresh token if available
        let refreshCookies = loginCookies.filter { $0.name.starts(with: "steamRefresh_") && !$0.value.isEmpty }
        if let refreshToken = refreshCookies.first?.value {
            KeychainHelper.saveRefreshToken(accountName: accountName, token: refreshToken)
        }
    }

    private func saveMaFile(_ auth: NewAuthenticator, fullyEnrolled: Bool = false) {
        let maFilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/steamguard-cli/maFiles")
        try? FileManager.default.createDirectory(at: maFilesDir, withIntermediateDirectories: true)

        let accountName = auth.accountName.isEmpty ? username : auth.accountName

        let maData: [String: Any] = [
            "account_name": accountName,
            "steam_id": auth.steamId,
            "shared_secret": auth.sharedSecret,
            "identity_secret": auth.identitySecret,
            "revocation_code": auth.revocationCode,
            "serial_number": auth.serialNumber,
            "token_gid": auth.tokenGid,
            "secret_1": auth.secret1,
            "uri": auth.uri,
            "device_id": auth.deviceId,
            "fully_enrolled": fullyEnrolled,
            "server_time": auth.serverTime
            // Note: Access tokens are stored in encrypted session storage, NOT in plaintext maFiles
        ]

        let filePath = maFilesDir.appendingPathComponent("\(accountName).maFile")
        if let jsonData = try? JSONSerialization.data(withJSONObject: maData, options: .prettyPrinted) {
            try? jsonData.write(to: filePath)
        }
    }

    private func saveToManifest(_ auth: NewAuthenticator) {
        let maFilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/steamguard-cli/maFiles")
        let manifestPath = maFilesDir.appendingPathComponent("manifest.json")

        let accountName = auth.accountName.isEmpty ? username : auth.accountName

        var manifest: [String: Any]
        if let data = try? Data(contentsOf: manifestPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            manifest = existing
        } else {
            manifest = ["entries": [[String: Any]](), "version": 1]
        }

        var entries = manifest["entries"] as? [[String: Any]] ?? []

        // Remove existing entry for this account
        entries.removeAll { ($0["filename"] as? String)?.contains(accountName) == true }

        entries.append([
            "filename": "\(accountName).maFile",
            "steamid": auth.steamId
        ])

        manifest["entries"] = entries

        if let jsonData = try? JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted) {
            try? jsonData.write(to: manifestPath)
        }
    }
}
