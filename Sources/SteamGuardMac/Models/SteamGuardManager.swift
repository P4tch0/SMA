import Foundation

/// Loads and manages Steam accounts from steamguard-cli's maFiles directory.
class SteamGuardManager: ObservableObject {
    @Published var accounts: [SteamAccount] = []
    @Published var errorMessage: String?

    private let maFilesPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        maFilesPath = "\(home)/Library/Application Support/steamguard-cli/maFiles"
        loadAccounts()
    }

    func loadAccounts() {
        let manifestPath = "\(maFilesPath)/manifest.json"

        guard FileManager.default.fileExists(atPath: manifestPath) else {
            errorMessage = "No manifest found at \(maFilesPath). Import accounts with steamguard-cli first."
            return
        }

        do {
            let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
            let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

            var loaded: [SteamAccount] = []
            for entry in manifest.entries {
                let filePath = "\(maFilesPath)/\(entry.filename)"
                guard FileManager.default.fileExists(atPath: filePath) else { continue }
                let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                let account = try JSONDecoder().decode(SteamAccount.self, from: data)
                loaded.append(account)
            }

            accounts = loaded
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load accounts: \(error.localizedDescription)"
        }
    }

    func generateCode(for account: SteamAccount) -> String {
        SteamTOTP.generateCode(sharedSecret: account.sharedSecret)
    }
}
