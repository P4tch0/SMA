import Foundation

/// Handles importing Steam Guard authenticator data from Android devices via ADB,
/// or from manually provided files. This allows users to clone their authenticator
/// to SMA without removing it from their phone — avoiding the 15-day trade hold.
///
/// Supported methods:
/// 1. ADB auto-pull (rooted + non-rooted via `run-as`)
/// 2. Manual file import (drag & drop or file picker)
///
/// The authenticator secrets are read-only — nothing is modified on the phone.
enum PhoneImporter {

    // MARK: - Types

    struct ImportedAccount {
        let accountName: String
        let steamId: UInt64
        let sharedSecret: String
        let identitySecret: String
        let revocationCode: String
        let serialNumber: String
        let tokenGid: String
        let secret1: String
        let uri: String
        let deviceId: String
        let serverTime: UInt64
    }

    enum ImportError: LocalizedError {
        case adbNotInstalled
        case noDeviceConnected
        case multipleDevices
        case noSteamguardFiles
        case extractionFailed(String)
        case parseError(String)
        case fileNotFound

        var errorDescription: String? {
            switch self {
            case .adbNotInstalled:
                return "ADB is not installed. Install it with: brew install android-platform-tools"
            case .noDeviceConnected:
                return "No Android device found. Make sure USB Debugging is enabled and the device is connected."
            case .multipleDevices:
                return "Multiple devices connected. Please connect only the phone you want to import from."
            case .noSteamguardFiles:
                return "No Steam Guard data found on this device. Make sure the Steam app is installed and has an authenticator set up."
            case .extractionFailed(let detail):
                return "Failed to extract data: \(detail)"
            case .parseError(let detail):
                return "Failed to parse Steam Guard data: \(detail)"
            case .fileNotFound:
                return "File not found."
            }
        }
    }

    // MARK: - ADB Helpers

    /// Check if ADB is installed and return its path
    static func findADB() -> String? {
        let paths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        // Try `which adb`
        if let result = shell("which adb"), !result.isEmpty {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Check if ADB is installed
    static var isADBInstalled: Bool { findADB() != nil }

    /// List connected Android devices
    static func connectedDevices() throws -> [String] {
        guard let adb = findADB() else { throw ImportError.adbNotInstalled }

        guard let output = shell("\(adb) devices") else {
            throw ImportError.extractionFailed("Failed to run adb devices")
        }

        let lines = output.components(separatedBy: "\n")
        var devices: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("device") && !trimmed.starts(with: "List") {
                let serial = trimmed.replacingOccurrences(of: "\tdevice", with: "")
                    .replacingOccurrences(of: " device", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !serial.isEmpty { devices.append(serial) }
            }
        }
        return devices
    }

    // MARK: - Extract from Phone

    /// Attempt to extract Steam Guard files from a connected Android device.
    /// Tries multiple methods in order of reliability.
    static func extractFromPhone() throws -> [ImportedAccount] {
        guard let adb = findADB() else { throw ImportError.adbNotInstalled }

        let devices = try connectedDevices()
        if devices.isEmpty { throw ImportError.noDeviceConnected }
        if devices.count > 1 { throw ImportError.multipleDevices }

        let steamPackage = "com.valvesoftware.android.steam.community"
        let steamFilesDir = "/data/data/\(steamPackage)/files"

        // Method 1: `run-as` (works on most devices without root)
        if let accounts = tryRunAs(adb: adb, package: steamPackage, filesDir: steamFilesDir) {
            return accounts
        }

        // Method 2: `su` for rooted devices
        if let accounts = tryRoot(adb: adb, filesDir: steamFilesDir) {
            return accounts
        }

        // Method 3: Try accessing via content provider or alternative paths
        if let accounts = tryAlternativePaths(adb: adb, package: steamPackage) {
            return accounts
        }

        throw ImportError.noSteamguardFiles
    }

    /// Method 1: Use `run-as` to access Steam app's private data
    private static func tryRunAs(adb: String, package: String, filesDir: String) -> [ImportedAccount]? {
        // List Steamguard files
        guard let listing = shell("\(adb) shell run-as \(package) ls files/"),
              listing.contains("Steamguard-") else {
            return nil
        }

        let files = listing.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.starts(with: "Steamguard-") }

        if files.isEmpty { return nil }

        var accounts: [ImportedAccount] = []
        for file in files {
            if let content = shell("\(adb) shell run-as \(package) cat files/\(file)"),
               !content.isEmpty,
               let account = parseGuardFile(content) {
                accounts.append(account)
            }
        }

        return accounts.isEmpty ? nil : accounts
    }

    /// Method 2: Use `su` (root) to access Steam app's private data
    private static func tryRoot(adb: String, filesDir: String) -> [ImportedAccount]? {
        // Check if device is rooted
        guard let rootCheck = shell("\(adb) shell su -c 'id'"),
              rootCheck.contains("uid=0") else {
            return nil
        }

        guard let listing = shell("\(adb) shell su -c 'ls \(filesDir)/'"),
              listing.contains("Steamguard-") else {
            return nil
        }

        let files = listing.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.starts(with: "Steamguard-") }

        if files.isEmpty { return nil }

        var accounts: [ImportedAccount] = []
        for file in files {
            if let content = shell("\(adb) shell su -c 'cat \(filesDir)/\(file)'"),
               !content.isEmpty,
               let account = parseGuardFile(content) {
                accounts.append(account)
            }
        }

        return accounts.isEmpty ? nil : accounts
    }

    /// Method 3: Try alternative access methods
    private static func tryAlternativePaths(adb: String, package: String) -> [ImportedAccount]? {
        // Try copying to sdcard first (rooted)
        let tmpPath = "/sdcard/Download/.sma_tmp_export"
        let filesDir = "/data/data/\(package)/files"

        _ = shell("\(adb) shell su -c 'cp \(filesDir)/Steamguard-* \(tmpPath)/ 2>/dev/null'")

        // Try to pull from sdcard
        guard let listing = shell("\(adb) shell ls \(tmpPath)/"),
              listing.contains("Steamguard-") else {
            // Cleanup
            _ = shell("\(adb) shell rm -rf \(tmpPath)")
            return nil
        }

        let files = listing.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.starts(with: "Steamguard-") }

        var accounts: [ImportedAccount] = []
        for file in files {
            if let content = shell("\(adb) shell cat \(tmpPath)/\(file)"),
               !content.isEmpty,
               let account = parseGuardFile(content) {
                accounts.append(account)
            }
        }

        // Cleanup temp files
        _ = shell("\(adb) shell rm -rf \(tmpPath)")

        return accounts.isEmpty ? nil : accounts
    }

    // MARK: - Parse

    /// Parse a Steamguard JSON file into an ImportedAccount
    static func parseGuardFile(_ content: String) -> ImportedAccount? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseGuardJSON(json)
    }

    /// Parse a Steamguard JSON dictionary into an ImportedAccount
    static func parseGuardJSON(_ json: [String: Any]) -> ImportedAccount? {
        guard let sharedSecret = json["shared_secret"] as? String, !sharedSecret.isEmpty else {
            return nil
        }

        let accountName = json["account_name"] as? String ?? ""

        let steamId: UInt64
        if let sid = json["steamid"] as? UInt64 { steamId = sid }
        else if let sid = json["steamid"] as? Int { steamId = UInt64(sid) }
        else if let s = json["steamid"] as? String, let sid = UInt64(s) { steamId = sid }
        else if let sid = json["steam_id"] as? UInt64 { steamId = sid }
        else if let s = json["steam_id"] as? String, let sid = UInt64(s) { steamId = sid }
        // Try Session.SteamID
        else if let session = json["Session"] as? [String: Any] {
            if let sid = session["SteamID"] as? UInt64 { steamId = sid }
            else if let sid = session["SteamID"] as? Int { steamId = UInt64(sid) }
            else { steamId = 0 }
        } else { steamId = 0 }

        let serverTime: UInt64
        if let t = json["server_time"] as? UInt64 { serverTime = t }
        else if let s = json["server_time"] as? String, let t = UInt64(s) { serverTime = t }
        else if let t = json["server_time"] as? Int { serverTime = UInt64(t) }
        else { serverTime = UInt64(Date().timeIntervalSince1970) }

        return ImportedAccount(
            accountName: accountName,
            steamId: steamId,
            sharedSecret: sharedSecret,
            identitySecret: json["identity_secret"] as? String ?? "",
            revocationCode: json["revocation_code"] as? String ?? "",
            serialNumber: json["serial_number"] as? String ?? "",
            tokenGid: json["token_gid"] as? String ?? "",
            secret1: json["secret_1"] as? String ?? "",
            uri: json["uri"] as? String ?? "",
            deviceId: json["device_id"] as? String ?? "",
            serverTime: serverTime
        )
    }

    // MARK: - Save imported account

    /// Save an imported account as a maFile and update the manifest
    static func saveAccount(_ account: ImportedAccount) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let maFilesDir = home.appendingPathComponent("Library/Application Support/steamguard-cli/maFiles")
        try FileManager.default.createDirectory(at: maFilesDir, withIntermediateDirectories: true)

        // Build maFile JSON
        let maData: [String: Any] = [
            "account_name": account.accountName,
            "steam_id": account.steamId,
            "shared_secret": account.sharedSecret,
            "identity_secret": account.identitySecret,
            "revocation_code": account.revocationCode,
            "serial_number": account.serialNumber,
            "token_gid": account.tokenGid,
            "secret_1": account.secret1,
            "uri": account.uri,
            "device_id": account.deviceId,
            "server_time": account.serverTime,
            "fully_enrolled": true
        ]

        let fileName = account.accountName.isEmpty
            ? "\(account.steamId).maFile"
            : "\(account.accountName).maFile"

        let filePath = maFilesDir.appendingPathComponent(fileName)
        let jsonData = try JSONSerialization.data(withJSONObject: maData, options: .prettyPrinted)
        try jsonData.write(to: filePath)

        // Create per-account session folder so it exists when user logs in later
        let sessionAccountName = account.accountName.isEmpty ? String(account.steamId) : account.accountName
        KeychainHelper.ensureAccountDir(for: sessionAccountName)

        // Update manifest
        let manifestPath = maFilesDir.appendingPathComponent("manifest.json")
        var manifest: [String: Any]
        if let data = try? Data(contentsOf: manifestPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            manifest = existing
        } else {
            manifest = ["entries": [[String: Any]](), "version": 1]
        }

        var entries = manifest["entries"] as? [[String: Any]] ?? []
        entries.removeAll { ($0["filename"] as? String) == fileName }
        entries.append(["filename": fileName, "steamid": account.steamId])
        manifest["entries"] = entries

        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
        try manifestData.write(to: manifestPath)
    }

    // MARK: - Shell

    /// Run a shell command and return stdout
    private static func shell(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
