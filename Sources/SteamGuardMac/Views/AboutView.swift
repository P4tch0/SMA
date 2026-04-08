import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hoveredLink: String?

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    var body: some View {
        VStack(spacing: 0) {
            // Close
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
            .padding(.trailing, 16)

            // Header
            VStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)

                Text("Steam Mac Authenticator")
                    .font(.title2.bold())

                Text("v\(version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1))
                    .cornerRadius(6)
            }

            // Privacy section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Privacy & Security")

                infoRow(icon: "lock.fill", color: .green,
                    text: "Passwords never stored — login happens on Steam's official site.")
                infoRow(icon: "key.fill", color: .blue,
                    text: "Sessions encrypted with AES-256-GCM, stored locally on your Mac.")
                infoRow(icon: "server.rack", color: .orange,
                    text: "No third-party servers. All traffic goes directly to Steam.")
                infoRow(icon: "eye.slash.fill", color: .purple,
                    text: "Open source — review every line of code yourself.")
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)

            // Contact section
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Contact & Feedback")

                HStack(spacing: 16) {
                    contactLink(icon: "steamSymbol", label: "Patcho", url: "https://steamcommunity.com/id/Patcho", id: "steam")
                    contactLink(icon: "paperplane.fill", label: "@Yazan", url: "https://t.me/Yazan", id: "telegram")
                    contactLink(icon: "at", label: "@PatchoCSGO", url: "https://x.com/PatchoCSGO", id: "twitter")
                }

                Text("Found a bug or have a suggestion? Reach out on any platform above.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)

            Spacer()

            // Footer
            VStack(spacing: 4) {
                Text("Made with care for the Steam community")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                Text("Not affiliated with Valve Corporation.")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.bottom, 16)
        }
        .frame(width: 440, height: 480)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary.opacity(0.8))
            Rectangle()
                .fill(.secondary.opacity(0.15))
                .frame(height: 1)
        }
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func contactLink(icon: String, label: String, url: String, id: String) -> some View {
        Button {
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 5) {
                if icon == "steamSymbol" {
                    // Steam doesn't have an SF Symbol — use a game controller
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 11))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(hoveredLink == id ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.06))
            .foregroundColor(hoveredLink == id ? .blue : .primary.opacity(0.7))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hoveredLink = h ? id : nil }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
