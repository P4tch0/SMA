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
    @State private var isDragHovered = false
    @State private var done = false

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
            } else {
                importView
            }

            // Error
            if let error = errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 13))
                    Text(error).font(.caption).foregroundColor(.primary.opacity(0.8))
                    Spacer()
                }
                .padding(12)
                .background(.orange.opacity(0.08))
            }
        }
        .frame(minWidth: 480, idealWidth: 500, minHeight: 380, idealHeight: 440)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json, .data, UTType(filenameExtension: "maFile") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
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

                Text("Drop maFile here")
                    .font(.title3.bold())

                Text("or")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    showFileImporter = true
                } label: {
                    Text("Browse Files")
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

            // Supported formats
            VStack(spacing: 8) {
                Text("Supported formats")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    formatBadge(".maFile", detail: "SDA / steamguard-cli")
                    formatBadge("Steamguard-*", detail: "Android backup")
                    formatBadge(".json", detail: "Any JSON export")
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
                    importFile(at: url)
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                importFile(at: url)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importFile(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            errorMessage = nil

            // Try JSON
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let account = PhoneImporter.parseGuardJSON(json) {
                try PhoneImporter.saveAccount(account)
                importedAccounts.append(account)
                done = true
                return
            }

            // Try as text (BOM, whitespace)
            if let text = String(data: data, encoding: .utf8),
               let account = PhoneImporter.parseGuardFile(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                try PhoneImporter.saveAccount(account)
                importedAccounts.append(account)
                done = true
                return
            }

            errorMessage = "Could not parse \(url.lastPathComponent). Make sure it's a valid maFile or Steamguard JSON."
        } catch {
            errorMessage = "Failed to import: \(error.localizedDescription)"
        }
    }
}
