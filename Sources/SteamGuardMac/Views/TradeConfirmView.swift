import SwiftUI
import WebKit

struct TradeConfirmView: View {
    let account: SteamAccount
    @StateObject private var manager = TradeConfirmationManager()
    @Environment(\.dismiss) private var dismiss
    @State private var showingLogin = false
    @State private var selectedConfirmation: TradeConfirmation?
    @State private var showingDetails = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trade Confirmations")
                        .font(.headline)
                    Text(account.accountName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                if KeychainHelper.hasSession(accountName: account.accountName) {
                    Button {
                        KeychainHelper.deleteSession(accountName: account.accountName)
                        manager.needsLogin = true
                        manager.confirmations = []
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    Task { await manager.fetchConfirmations(for: account) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

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

            // Content
            if manager.isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView().scaleEffect(1.2)
                    Text("Loading confirmations...").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
            } else if manager.needsLogin {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "person.badge.key.fill").font(.system(size: 40)).foregroundStyle(.blue)
                    Text("Login Required").font(.title3.bold())
                    Text("Log in to Steam to view and manage trade confirmations.")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
                    Button { showingLogin = true } label: {
                        Label("Log in to Steam", systemImage: "lock.open.fill").font(.body.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Spacer()
            } else if let error = manager.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundStyle(.orange)
                    Text(error).font(.subheadline).multilineTextAlignment(.center).foregroundColor(.secondary).frame(maxWidth: 350)
                }
                Spacer()
            } else if manager.confirmations.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 36)).foregroundStyle(.green)
                    Text(manager.statusMessage ?? "No pending confirmations.").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.confirmations) { confirmation in
                            ConfirmationRow(
                                confirmation: confirmation,
                                partner: manager.partnerInfo[confirmation.id],
                                onDetails: {
                                    selectedConfirmation = confirmation
                                    showingDetails = true
                                },
                                onRespond: { accept in
                                    Task { await manager.respondToConfirmation(confirmation, accept: accept, account: account) }
                                }
                            )
                            Divider().padding(.leading, 72)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let status = manager.statusMessage, !manager.confirmations.isEmpty {
                HStack {
                    Image(systemName: "info.circle").foregroundColor(.blue)
                    Text(status).font(.caption)
                }
                .padding(8).frame(maxWidth: .infinity).background(.blue.opacity(0.05))
            }
        }
        .frame(minWidth: 580, idealWidth: 620, minHeight: 420, idealHeight: 500)
        .task { await manager.fetchConfirmations(for: account) }
        .sheet(isPresented: $showingLogin) {
            SteamLoginView(account: account) {
                Task { await manager.fetchConfirmations(for: account) }
            }
        }
        .sheet(isPresented: $showingDetails) {
            if let conf = selectedConfirmation {
                ConfirmationDetailView(confirmation: conf, account: account, manager: manager)
            }
        }
    }
}

// MARK: - Confirmation Row

struct ConfirmationRow: View {
    let confirmation: TradeConfirmation
    let partner: PartnerInfo?
    let onDetails: () -> Void
    let onRespond: (Bool) -> Void
    @State private var isHovered = false
    @State private var isDetailHovered = false

    /// Extract partner name from headline like "Trade with Username"
    private var partnerName: String? {
        // Prefer miniprofile name
        if let name = partner?.name, name != "Unknown" { return name }
        let h = confirmation.headline
        if let range = h.range(of: "with ", options: .caseInsensitive) {
            let name = String(h[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        return nil
    }

    private var avatarURL: URL? {
        // Prefer miniprofile avatar
        if let urlStr = partner?.avatarURL, let url = URL(string: urlStr) { return url }
        if let iconStr = confirmation.iconURL {
            let full = iconStr.hasPrefix("http") ? iconStr : "https://steamcommunity.com\(iconStr)"
            return URL(string: full)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar + Info — clickable for details
            Button(action: onDetails) {
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        if let url = avatarURL {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8).fill(confirmationColor.opacity(0.12))
                                    ProgressView().scaleEffect(0.5)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(confirmationColor.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: confirmationIcon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(confirmationColor)
                            }
                        }

                        // Level badge
                        if let level = partner?.level, level > 0 {
                            Text("\(level)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(levelColor(level))
                                .cornerRadius(4)
                                .offset(x: 4, y: 4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(confirmation.title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            if let time = confirmation.creationTime {
                                Text(timeAgo(time))
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }

                        if let name = partnerName {
                            HStack(spacing: 5) {
                                Text(name)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)

                                if let level = partner?.level, level > 0 {
                                    Text("Lv \(level)")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(levelColor(level).opacity(0.15))
                                        .foregroundColor(levelColor(level))
                                        .cornerRadius(4)
                                }
                            }
                        } else if !confirmation.headline.isEmpty {
                            Text(confirmation.headline)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                        }

                        if !confirmation.summary.isEmpty {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 1) {
                                    ForEach(confirmation.summary, id: \.self) { line in
                                        Text(line)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                // Subtle hint that appears on hover
                                if isDetailHovered {
                                    Text("View details")
                                        .font(.caption2)
                                        .foregroundColor(.blue.opacity(0.7))
                                        .transition(.opacity)
                                }
                            }
                        }
                    }
                }
                .scaleEffect(isDetailHovered ? 1.01 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isDetailHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isDetailHovered = hovering }
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help("Click to view trade details")

            Spacer()

            // Accept / Deny
            HStack(spacing: 5) {
                Button { onRespond(true) } label: {
                    Label(confirmation.acceptLabel, systemImage: "checkmark")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button { onRespond(false) } label: {
                    Label(confirmation.cancelLabel, systemImage: "xmark")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(isHovered ? Color.primary.opacity(0.03) : .clear)
        .onHover { isHovered = $0 }
    }

    private var confirmationIcon: String {
        switch confirmation.type {
        case 2: return "arrow.left.arrow.right"
        case 3: return "storefront"
        default: return "shippingbox.fill"
        }
    }

    private var confirmationColor: Color {
        switch confirmation.type {
        case 2: return .orange
        case 3: return .purple
        default: return .blue
        }
    }

    private func levelColor(_ level: Int) -> Color {
        if level >= 100 { return .red }
        if level >= 50 { return .purple }
        if level >= 20 { return .blue }
        if level >= 10 { return .green }
        return .gray
    }

    private func timeAgo(_ timestamp: UInt64) -> String {
        let seconds = Int(Date().timeIntervalSince1970) - Int(timestamp)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

// MARK: - Confirmation Detail View (WebView)

struct ConfirmationDetailView: View {
    let confirmation: TradeConfirmation
    let account: SteamAccount
    let manager: TradeConfirmationManager
    @Environment(\.dismiss) private var dismiss
    @State private var detailsHTML: String?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Confirmation Details")
                        .font(.headline)
                    Text(confirmation.headline.isEmpty ? confirmation.title : confirmation.headline)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                if isLoading {
                    ProgressView().scaleEffect(0.7)
                }

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

            if let html = detailsHTML {
                ConfirmationDetailWebView(html: html, isLoading: $isLoading)
            } else if loadFailed {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(.orange)
                    Text("Failed to load details.").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
            } else {
                Spacer()
                ProgressView("Loading details...")
                Spacer()
            }
        }
        .frame(minWidth: 500, idealWidth: 550, minHeight: 450, idealHeight: 550)
        .task {
            if let html = await manager.fetchDetailsHTML(for: confirmation, account: account) {
                detailsHTML = html
            } else {
                loadFailed = true
            }
        }
    }
}

struct ConfirmationDetailWebView: NSViewRepresentable {
    let html: String
    @Binding var isLoading: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: URL(string: "https://steamcommunity.com"))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading) }

    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        init(isLoading: Binding<Bool>) { self._isLoading = isLoading }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.isLoading = true }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.isLoading = false }
        }
    }
}
