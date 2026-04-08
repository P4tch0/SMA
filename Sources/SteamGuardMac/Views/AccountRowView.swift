import SwiftUI

struct AccountRowView: View {
    let account: SteamAccount
    let code: String
    let secondsRemaining: Int
    let isCopied: Bool
    let onCopy: () -> Void
    let onConfirmTrades: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false
    @State private var codeHovered = false
    @State private var tradeHovered = false
    @State private var showRemoveConfirm = false

    private var timerColor: Color {
        if secondsRemaining <= 5 { return .red }
        if secondsRemaining <= 10 { return .orange }
        return .blue
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                Text(String(account.accountName.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }

            // Account info
            VStack(alignment: .leading, spacing: 3) {
                Text(account.accountName)
                    .font(.system(.body, weight: .semibold))
                if let steamID = account.steamID {
                    Text(String(steamID))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .frame(minWidth: 100, alignment: .leading)

            Spacer()

            // Code — clickable to copy
            Button(action: onCopy) {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        if isCopied {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                                .transition(.scale.combined(with: .opacity))
                        }

                        Text(code)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundColor(isCopied ? .green : .primary)
                    }
                    .animation(.easeOut(duration: 0.2), value: isCopied)

                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .stroke(timerColor.opacity(0.15), lineWidth: 2)
                                .frame(width: 16, height: 16)
                            Circle()
                                .trim(from: 0, to: Double(secondsRemaining) / 30.0)
                                .stroke(timerColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 16, height: 16)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: secondsRemaining)
                        }

                        if codeHovered && !isCopied {
                            Text("Click to copy")
                                .font(.system(size: 9))
                                .foregroundColor(.blue.opacity(0.7))
                                .transition(.opacity)
                        } else {
                            Text("\(secondsRemaining)s")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(timerColor)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(codeHovered ? Color.blue.opacity(0.04) : .clear)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .onHover { h in
                withAnimation(.easeOut(duration: 0.15)) { codeHovered = h }
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            // Trade confirmations — labeled button with hover expand
            Button(action: onConfirmTrades) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                    if tradeHovered {
                        Text("Confirmations")
                            .font(.caption2.weight(.medium))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .onHover { h in
                withAnimation(.easeOut(duration: 0.15)) { tradeHovered = h }
            }

            // Hide button — visible on hover with label
            if isHovered {
                Button { showRemoveConfirm = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9, weight: .medium))
                        Text("Remove")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.08))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Remove account from SMA")
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(isHovered ? Color.primary.opacity(0.025) : .clear)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { isHovered = h } }
        .alert("Remove Account", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { onRemove() }
        } message: {
            if let code = account.revocationCode, !code.isEmpty {
                Text("Remove \(account.accountName) from SMA?\n\nRecovery code: \(code)\nSave this somewhere safe before hiding.\n\nThe maFile stays on disk — you can re-import it anytime.")
            } else {
                Text("Remove \(account.accountName) from SMA? The maFile stays on disk — you can re-import it anytime.")
            }
        }
    }
}
