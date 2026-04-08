import SwiftUI

struct ContentView: View {
    @StateObject private var manager = SteamGuardManager()
    @State private var codes: [String: String] = [:]
    @State private var secondsRemaining: Int = 30
    @State private var copiedAccount: String?
    @State private var selectedAccount: SteamAccount?
    @State private var showingConfirmations = false
    @State private var showingAbout = false
    @State private var showingSetup = false
    @State private var showingImport = false

    // Hover states for header buttons
    @State private var importHovered = false
    @State private var addHovered = false
    @State private var reloadHovered = false
    @State private var infoHovered = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var timerColor: Color {
        if secondsRemaining <= 5 { return .red }
        if secondsRemaining <= 10 { return .orange }
        return .blue
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "shield.checkered")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 0) {
                    Text("SMA")
                        .font(.title3.bold())
                    Text("Steam Mac Authenticator")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !manager.accounts.isEmpty {
                    Text("\(manager.accounts.count) account\(manager.accounts.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.08))
                        .cornerRadius(8)
                }

                // Header buttons — all expand on hover
                headerButton(icon: "doc.badge.arrow.up", label: "Import maFile", isHovered: $importHovered) {
                    showingImport = true
                }

                headerButton(icon: "plus", label: "Add Steam Account", isHovered: $addHovered) {
                    showingSetup = true
                }

                headerButton(icon: "arrow.clockwise", label: "Reload", isHovered: $reloadHovered) {
                    manager.loadAccounts()
                    refreshCodes()
                }

                headerButton(icon: "info.circle", label: "About", isHovered: $infoHovered) {
                    showingAbout = true
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.bar)

            // Global timer bar
            if !manager.accounts.isEmpty {
                GeometryReader { geo in
                    Rectangle()
                        .fill(timerColor)
                        .frame(width: geo.size.width * (Double(secondsRemaining) / 30.0), height: 2)
                        .animation(.linear(duration: 1), value: secondsRemaining)
                }
                .frame(height: 2)
            } else {
                Divider()
            }

            // Body
            if let error = manager.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 350)
                }
                Spacer()
            } else if manager.accounts.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No accounts found")
                        .font(.headline)
                    Text("Use **Import maFile** to add an existing account\nor **Add Steam Account** to set up a new authenticator.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.accounts) { account in
                            AccountRowView(
                                account: account,
                                code: codes[account.accountName] ?? "-----",
                                secondsRemaining: secondsRemaining,
                                isCopied: copiedAccount == account.accountName,
                                onCopy: { copyCode(for: account) },
                                onConfirmTrades: {
                                    selectedAccount = account
                                    showingConfirmations = true
                                },
                                onRemove: {
                                    hideAccount(account)
                                }
                            )
                            Divider().padding(.leading, 72)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Status bar
            if !manager.accounts.isEmpty {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Codes synced with Steam")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Next refresh in \(secondsRemaining)s")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(timerColor)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
        .frame(minWidth: 600, minHeight: 340)
        .onAppear { refreshCodes() }
        .onReceive(timer) { _ in
            secondsRemaining = SteamTOTP.secondsRemaining()
            if secondsRemaining == 30 {
                refreshCodes()
            }
        }
        .sheet(isPresented: $showingConfirmations) {
            if let account = selectedAccount {
                TradeConfirmView(account: account)
            }
        }
        .sheet(isPresented: $showingImport) {
            ImportFileView {
                manager.loadAccounts()
                refreshCodes()
            }
        }
        .sheet(isPresented: $showingSetup) {
            SetupWizardView {
                manager.loadAccounts()
                refreshCodes()
            }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }

    // MARK: - Header Button

    private func headerButton(icon: String, label: String, isHovered: Binding<Bool>, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                if isHovered.wrappedValue {
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { isHovered.wrappedValue = h }
        }
    }

    // MARK: - Actions

    private func refreshCodes() {
        for account in manager.accounts {
            codes[account.accountName] = manager.generateCode(for: account)
        }
        secondsRemaining = SteamTOTP.secondsRemaining()
    }

    private func hideAccount(_ account: SteamAccount) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let manifestPath = home.appendingPathComponent("Library/Application Support/steamguard-cli/maFiles/manifest.json")

        if let data = try? Data(contentsOf: manifestPath),
           var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var entries = manifest["entries"] as? [[String: Any]] {

            entries.removeAll { entry in
                let filename = entry["filename"] as? String ?? ""
                return filename.contains(account.accountName) ||
                       filename.contains(String(account.steamID ?? 0))
            }

            manifest["entries"] = entries
            if let updated = try? JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted) {
                try? updated.write(to: manifestPath)
            }
        }

        KeychainHelper.deleteSession(accountName: account.accountName)
        manager.loadAccounts()
        refreshCodes()
    }

    private func copyCode(for account: SteamAccount) {
        guard let code = codes[account.accountName] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        withAnimation(.easeInOut(duration: 0.2)) {
            copiedAccount = account.accountName
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if copiedAccount == account.accountName {
                    copiedAccount = nil
                }
            }
        }
    }
}
