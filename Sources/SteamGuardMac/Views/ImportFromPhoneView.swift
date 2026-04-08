import SwiftUI
import UniformTypeIdentifiers

/// Import existing Steam Guard maFiles into SMA.
/// Supports .maFile, Steamguard JSON, and SDA exports.
/// This preserves the existing authenticator — no trade hold.
struct ImportFileView: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: () -> Void

    @State private var importedAccounts: [PhoneImporter.ImportedAccount] = []
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    // showFolderImporter removed — single picker handles both files and folders
    @State private var isDragHovered = false
    @State private var done = false

    // Encrypted folder handling — inline password prompt
    @State private var encryptedFolderURL: URL?
    @State private var encryptedManifestEntries: [SDADecryptor.ManifestEntry] = []
    @State private var encryptedFileDataByName: [String: Data] = [:]
    @State private var encryptionPassword = ""
    @State private var isDecrypting = false

    // Single encrypted file with manifest found nearby
    @State private var pendingEncryptedData: Data?
    @State private var pendingEncryptedFilename: String = ""
    @State private var pendingManifestEntries: [SDADecryptor.ManifestEntry]?

    /// Whether we are showing the inline password prompt for encrypted files
    private var showingPasswordPrompt: Bool {
        !encryptedManifestEntries.isEmpty || (pendingEncryptedData != nil && pendingManifestEntries != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.badge.arrow.up.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Import maFile")
                        .font(.headline)
                    Text(done ? "Import Complete" : "Add existing authenticator to SMA")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            Divider()

            if done {
                successView
            } else if showingPasswordPrompt {
                passwordPromptView
            } else {
                importView
            }
        }
        .frame(minWidth: 480, idealWidth: 500, minHeight: 380, idealHeight: 440)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        importFolder(at: url)
                    } else {
                        importFile(at: url)
                    }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Import View

    private var importView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Drop zone
            VStack(spacing: 14) {
                Image(systemName: isDragHovered ? "arrow.down.doc.fill" : "doc.badge.arrow.up")
                    .font(.system(size: 36))
                    .foregroundStyle(isDragHovered ? .green : .blue)
                    .animation(.easeOut(duration: 0.15), value: isDragHovered)

                Text("Drop maFiles or SDA folder here")
                    .font(.title3.bold())

                Text("or")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    showFileImporter = true
                } label: {
                    Text("Browse")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDragHovered ? Color.green : Color.secondary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDragHovered ? Color.green.opacity(0.04) : .clear)
                    )
            )
            .padding(.horizontal, 24)
            .onDrop(of: [.fileURL], isTargeted: $isDragHovered) { providers in
                handleDrop(providers)
                return true
            }

            // Error message — inline, clearly visible
            if let error = errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 14))
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.orange.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal, 24)
            }

            // Supported formats
            VStack(spacing: 8) {
                Text("Supported formats")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    formatBadge(".maFile", detail: "SDA / steamguard-cli")
                    formatBadge("Steamguard-*", detail: "Android backup")
                    formatBadge("SDA Folder", detail: "Encrypted or plain")
                }
            }

            // Info note
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundColor(.blue).font(.system(size: 12))
                Text("If you have an existing authenticator on your phone and import its maFile here, **both devices will generate the same codes** — no trade hold.")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    // MARK: - Inline Password Prompt View

    private var passwordPromptView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Encrypted maFiles Detected")
                .font(.title3.bold())

            let fileCount = encryptedManifestEntries.isEmpty
                ? 1
                : encryptedFileDataByName.count

            Text("Found **\(fileCount) encrypted file\(fileCount == 1 ? "" : "s")**. Enter your SDA encryption passkey to decrypt.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                SecureField("SDA encryption passkey", text: $encryptionPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .onSubmit { decryptAllPending() }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        cancelEncryption()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        decryptAllPending()
                    } label: {
                        if isDecrypting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.horizontal, 8)
                        } else {
                            Text("Decrypt & Import")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(encryptionPassword.isEmpty || isDecrypting)
                }
            }

            // Error message inline
            if let error = errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 14))
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.orange.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Import Successful!")
                .font(.title3.bold())

            Text("**\(importedAccounts.count) account\(importedAccounts.count == 1 ? "" : "s")** imported.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(importedAccounts, id: \.accountName) { account in
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.accountName.isEmpty ? "Steam ID: \(account.steamId)" : account.accountName)
                                .font(.subheadline.weight(.medium))
                            if !account.revocationCode.isEmpty {
                                Text("Recovery: \(account.revocationCode)")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.green.opacity(0.04))
                    .cornerRadius(6)
                }
            }
            .frame(maxWidth: 340)

            Button {
                onComplete()
                dismiss()
            } label: {
                Text("Done")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: 200)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func formatBadge(_ name: String, detail: String) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundColor(.blue)
            Text(detail)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.blue.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - File Handling

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        importFolder(at: url)
                    } else {
                        importFile(at: url)
                    }
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Check if manifest.json is among the selected files
            var manifestEntries: [SDADecryptor.ManifestEntry]?
            var encryptedFiles: [(URL, Data)] = []
            var unencryptedURLs: [URL] = []

            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                if url.lastPathComponent.lowercased() == "manifest.json" {
                    if let data = try? Data(contentsOf: url),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let entries = json["entries"] as? [[String: Any]] {
                        manifestEntries = entries.compactMap { entry in
                            guard let filename = entry["filename"] as? String,
                                  let ivB64 = entry["encryption_iv"] as? String,
                                  let saltB64 = entry["encryption_salt"] as? String,
                                  let iv = Data(base64Encoded: ivB64),
                                  let salt = Data(base64Encoded: saltB64) else { return nil }
                            return SDADecryptor.ManifestEntry(filename: filename, iv: iv, salt: salt)
                        }
                    }
                    continue
                }

                if let data = try? Data(contentsOf: url), SDADecryptor.isEncrypted(data) {
                    encryptedFiles.append((url, data))
                } else {
                    unencryptedURLs.append(url)
                }
            }

            // Import unencrypted files directly
            for url in unencryptedURLs {
                importFile(at: url)
            }

            // Handle encrypted files with manifest
            if !encryptedFiles.isEmpty {
                if let entries = manifestEntries, !entries.isEmpty {
                    // We have manifest — load encrypted data and show password prompt
                    var fileData: [String: Data] = [:]
                    for (url, data) in encryptedFiles {
                        fileData[url.lastPathComponent] = data
                    }
                    encryptedManifestEntries = entries
                    encryptedFileDataByName = fileData
                    encryptionPassword = ""
                    errorMessage = nil
                    // Password prompt will show via showingPasswordPrompt
                } else {
                    errorMessage = "Encrypted maFile\(encryptedFiles.count > 1 ? "s" : "") detected. Select the manifest.json file together with the maFiles (hold Cmd to select multiple files)."
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFolder(at: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Import Single File

    private func importFile(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            errorMessage = nil

            // Try JSON (unencrypted)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let account = PhoneImporter.parseGuardJSON(json) {
                try PhoneImporter.saveAccount(account)
                importedAccounts.append(account)
                done = true
                return
            }

            // Try as text with various encodings
            let encodings: [String.Encoding] = [.utf8, .utf16, .ascii]
            for encoding in encodings {
                if let text = String(data: data, encoding: encoding)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let account = PhoneImporter.parseGuardFile(text) {
                    try PhoneImporter.saveAccount(account)
                    importedAccounts.append(account)
                    done = true
                    return
                }
            }

            // Check if file is SDA-encrypted
            if SDADecryptor.isEncrypted(data) {
                // Try to find manifest.json in the same folder (direct file access)
                let entries = SDADecryptor.findManifest(near: url)
                if let entries = entries, !entries.isEmpty {
                    pendingEncryptedData = data
                    pendingEncryptedFilename = url.lastPathComponent
                    pendingManifestEntries = entries
                    encryptionPassword = ""
                    errorMessage = nil
                    // Shows inline password prompt
                } else {
                    errorMessage = "Encrypted maFile — make sure manifest.json is in the same folder as your maFile, then try again."
                }
                return
            }

            let preview = String(data: data.prefix(100), encoding: .utf8) ?? "binary data"
            errorMessage = "Could not parse \(url.lastPathComponent). File starts with: \(preview.prefix(50))..."
        } catch {
            errorMessage = "Failed to read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - Import Folder (SDA maFiles directory)

    private func importFolder(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let manifestURL = url.appendingPathComponent("manifest.json")

        // First, try to import any unencrypted .maFile / .json files from the folder
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            errorMessage = "Could not read folder contents."
            return
        }

        // Check for manifest.json
        if let manifestData = try? Data(contentsOf: manifestURL),
           let manifestJSON = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] {

            let isEncrypted = manifestJSON["encrypted"] as? Bool ?? false

            if isEncrypted {
                // Parse manifest entries for IV/salt
                guard let entries = manifestJSON["entries"] as? [[String: Any]] else {
                    errorMessage = "manifest.json has no entries array."
                    return
                }

                let parsed = entries.compactMap { entry -> SDADecryptor.ManifestEntry? in
                    guard let filename = entry["filename"] as? String,
                          let ivB64 = entry["encryption_iv"] as? String,
                          let saltB64 = entry["encryption_salt"] as? String,
                          let iv = Data(base64Encoded: ivB64),
                          let salt = Data(base64Encoded: saltB64) else { return nil }
                    return SDADecryptor.ManifestEntry(filename: filename, iv: iv, salt: salt)
                }

                if parsed.isEmpty {
                    errorMessage = "manifest.json says encrypted but has no valid encryption entries."
                    return
                }

                // Load all encrypted maFile data
                var fileData: [String: Data] = [:]
                for entry in parsed {
                    let fileURL = url.appendingPathComponent(entry.filename)
                    if let data = try? Data(contentsOf: fileURL) {
                        fileData[entry.filename] = data
                    }
                }

                if fileData.isEmpty {
                    errorMessage = "Could not read any maFiles from the folder."
                    return
                }

                // Store state and show inline password prompt
                encryptedFolderURL = url
                encryptedManifestEntries = parsed
                encryptedFileDataByName = fileData
                encryptionPassword = ""
                errorMessage = nil
                return
            }
        }

        // Not encrypted (or no manifest) — try to import files directly
        var importedAny = false
        for fileURL in contents {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "mafile" || ext == "json" {
                if fileURL.lastPathComponent.lowercased() == "manifest.json" { continue }
                do {
                    let data = try Data(contentsOf: fileURL)

                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let account = PhoneImporter.parseGuardJSON(json) {
                        try PhoneImporter.saveAccount(account)
                        importedAccounts.append(account)
                        importedAny = true
                        continue
                    }

                    if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       let account = PhoneImporter.parseGuardFile(text) {
                        try PhoneImporter.saveAccount(account)
                        importedAccounts.append(account)
                        importedAny = true
                    }
                } catch {
                    // Skip files that fail to read
                }
            }
        }

        if importedAny {
            done = true
        } else {
            errorMessage = "No importable maFiles found in this folder."
        }
    }

    // MARK: - Decryption

    private func cancelEncryption() {
        encryptedFolderURL = nil
        encryptedManifestEntries = []
        encryptedFileDataByName = [:]
        pendingEncryptedData = nil
        pendingEncryptedFilename = ""
        pendingManifestEntries = nil
        encryptionPassword = ""
        errorMessage = nil
    }

    private func decryptAllPending() {
        guard !encryptionPassword.isEmpty else {
            errorMessage = "Enter the encryption passkey."
            return
        }

        isDecrypting = true
        errorMessage = nil

        // Case 1: Folder with multiple encrypted files
        if !encryptedManifestEntries.isEmpty {
            decryptFolder()
            return
        }

        // Case 2: Single encrypted file with manifest found nearby
        if let data = pendingEncryptedData, let entries = pendingManifestEntries {
            decryptSingleFile(data: data, filename: pendingEncryptedFilename, entries: entries)
            return
        }

        isDecrypting = false
        errorMessage = "No encrypted data pending."
    }

    private func decryptFolder() {
        var decryptedAccounts: [PhoneImporter.ImportedAccount] = []
        var failedFiles: [String] = []

        for entry in encryptedManifestEntries {
            guard let data = encryptedFileDataByName[entry.filename] else {
                failedFiles.append(entry.filename)
                continue
            }

            guard let decryptedData = SDADecryptor.decrypt(
                encryptedData: data,
                password: encryptionPassword,
                iv: entry.iv,
                salt: entry.salt
            ) else {
                // First failure likely means wrong password
                isDecrypting = false
                errorMessage = "Wrong passkey or corrupted file (\(entry.filename)). Check your SDA encryption password and try again."
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
                  let account = PhoneImporter.parseGuardJSON(json) else {
                failedFiles.append(entry.filename)
                continue
            }

            decryptedAccounts.append(account)
        }

        // Save all successfully decrypted accounts
        var savedCount = 0
        for account in decryptedAccounts {
            do {
                try PhoneImporter.saveAccount(account)
                importedAccounts.append(account)
                savedCount += 1
            } catch {
                failedFiles.append(account.accountName)
            }
        }

        isDecrypting = false

        if savedCount > 0 {
            encryptedFolderURL = nil
            encryptedManifestEntries = []
            encryptedFileDataByName = [:]
            encryptionPassword = ""

            if !failedFiles.isEmpty {
                errorMessage = "Imported \(savedCount) account(s) but failed to parse: \(failedFiles.joined(separator: ", "))"
            } else {
                errorMessage = nil
            }
            done = true
        } else {
            errorMessage = "Decryption succeeded but no valid accounts found in the files."
        }
    }

    private func decryptSingleFile(data: Data, filename: String, entries: [SDADecryptor.ManifestEntry]) {
        guard let entry = entries.first(where: { $0.filename == filename }) else {
            isDecrypting = false
            errorMessage = "No matching entry in manifest.json for \(filename)."
            return
        }

        guard let decryptedData = SDADecryptor.decrypt(
            encryptedData: data,
            password: encryptionPassword,
            iv: entry.iv,
            salt: entry.salt
        ) else {
            isDecrypting = false
            errorMessage = "Wrong passkey or corrupted file. Check your SDA encryption password and try again."
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
              let account = PhoneImporter.parseGuardJSON(json) else {
            isDecrypting = false
            errorMessage = "Decrypted successfully but couldn't parse the account data."
            return
        }

        do {
            try PhoneImporter.saveAccount(account)
            importedAccounts.append(account)
            pendingEncryptedData = nil
            pendingEncryptedFilename = ""
            pendingManifestEntries = nil
            encryptionPassword = ""
            errorMessage = nil
            isDecrypting = false
            done = true
        } catch {
            isDecrypting = false
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
