import SwiftUI

struct SetupWizardView: View {
    @StateObject private var setup = AuthenticatorSetup()
    @Environment(\.dismiss) private var dismiss
    let onComplete: () -> Void
    @State private var showingLogin = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "plus.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add Steam Guard")
                        .font(.headline)
                    Text(stepTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Progress dots
                HStack(spacing: 4) {
                    ForEach(0..<4) { i in
                        Circle()
                            .fill(i <= currentStepIndex ? Color.blue : Color.secondary.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }

                if setup.step != .done {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(.bar)

            Divider()

            // Content
            if setup.step == .login {
                loginPromptView
            } else {
            ScrollView {
                VStack(spacing: 20) {
                    switch setup.step {
                    case .login:
                        EmptyView() // handled above
                    case .phoneSetup:
                        phoneSetupView
                    case .phoneEmailConfirmation:
                        phoneEmailView
                    case .phoneSMSVerify:
                        phoneSMSView
                    case .addingAuthenticator:
                        progressView("Setting up authenticator...")
                    case .revocationCode:
                        revocationCodeView
                    case .finalizeSMS:
                        finalizeView
                    case .done:
                        doneView
                    }
                }
                .padding(24)
            }
            } // end else (non-login steps)

            // Error / Status bar
            if let error = setup.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    Text(error).font(.caption).foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.red.opacity(0.08))
            } else if let status = setup.statusMessage {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text(status).font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.blue.opacity(0.08))
            }
        }
        .frame(minWidth: 500, idealWidth: 520, minHeight: 480, idealHeight: 560)
    }

    // MARK: - Step Views

    private var loginPromptView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Sign in to Steam")
                .font(.title3.bold())

            Text("Sign in to the Steam account you want to protect with Steam Guard.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Button {
                showingLogin = true
            } label: {
                Label("Sign in with Steam", systemImage: "lock.open.fill")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error = setup.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 13))
                    Text(error).font(.caption).foregroundColor(.primary.opacity(0.8))
                }
                .padding(12)
                .frame(maxWidth: 360, alignment: .leading)
                .background(.orange.opacity(0.08))
                .cornerRadius(8)
            }

            if setup.isWorking {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text(setup.statusMessage ?? "Processing...")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(24)
        .sheet(isPresented: $showingLogin) {
            SetupSteamLoginView { cookies in
                showingLogin = false
                Task { await setup.handleWebViewLogin(cookies: cookies) }
            }
        }
    }

    private var phoneSetupView: some View {
        VStack(spacing: 16) {
            stepIcon("phone.fill", color: .green)
            Text("Phone Number Required").font(.title3.bold())
            Text("Steam requires a phone number to enable the authenticator. Enter your number including country code.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

            VStack(spacing: 8) {
                TextField("Phone number (e.g. +1234567890)", text: $setup.phoneNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }

            inlineError

            actionButton("Submit Phone Number", disabled: setup.phoneNumber.isEmpty) {
                Task { await setup.submitPhoneNumber() }
            }
            backButton { setup.step = .login; setup.loggedIn = false; setup.errorMessage = nil }
        }
    }

    private var phoneEmailView: some View {
        VStack(spacing: 16) {
            stepIcon("envelope.badge.fill", color: .orange)
            Text("Confirm Your Email").font(.title3.bold())
            Text("Steam sent a confirmation email to your account's email address. Click the link in the email, then tap the button below.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            actionButton("I've Confirmed My Email") {
                Task { await setup.checkEmailConfirmation() }
            }
            backButton { setup.step = .phoneSetup; setup.errorMessage = nil }
        }
    }

    private var phoneSMSView: some View {
        VStack(spacing: 16) {
            stepIcon("message.fill", color: .green)
            Text("Verify Phone Number").font(.title3.bold())
            Text("Steam sent an SMS code to your phone. Enter it below to verify.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

            TextField("SMS code", text: $setup.phoneSMSCode)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            inlineError

            actionButton("Verify", disabled: setup.phoneSMSCode.isEmpty) {
                Task { await setup.verifyPhoneSMS() }
            }
            backButton { setup.step = .phoneSetup; setup.phoneSMSCode = ""; setup.errorMessage = nil }
        }
    }

    private var revocationCodeView: some View {
        VStack(spacing: 16) {
            stepIcon("key.fill", color: .red)
            Text("Save Your Recovery Code").font(.title3.bold())

            VStack(spacing: 8) {
                Text("This is your recovery code. If you lose access to SMA, this is the ONLY way to remove the authenticator from your account.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                Text(setup.revocationCode)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                    .padding()
                    .background(.red.opacity(0.08))
                    .cornerRadius(12)
                    .textSelection(.enabled)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(setup.revocationCode, forType: .string)
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Write this code down and store it somewhere safe.\nDo NOT share it with anyone.")
                    .font(.caption2).foregroundColor(.orange).multilineTextAlignment(.center)
            }
            .padding(10)
            .background(.orange.opacity(0.06))
            .cornerRadius(8)

            Text("Steam will now send an SMS to your phone to finalize the setup.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

            actionButton("I've Saved My Code — Continue") {
                setup.step = .finalizeSMS
            }
        }
    }

    private var finalizeView: some View {
        VStack(spacing: 16) {
            stepIcon("checkmark.shield.fill", color: .blue)
            Text("Finalize Setup").font(.title3.bold())
            Text("Enter the SMS code Steam sent to your phone to complete the authenticator setup.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

            TextField("SMS code", text: $setup.finalizeSMSCode)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            inlineError

            actionButton("Finalize", disabled: setup.finalizeSMSCode.isEmpty) {
                Task { await setup.finalizeWithSMS() }
            }
            backButton { setup.step = .revocationCode; setup.finalizeSMSCode = ""; setup.errorMessage = nil }
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            stepIcon("checkmark.seal.fill", color: .green)
            Text("Steam Guard Active!").font(.title3.bold())
            Text("Your account **\(setup.username)** is now protected with Steam Guard via SMA. You'll see 2FA codes on the main screen.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            if !setup.revocationCode.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").foregroundColor(.red)
                    Text("Recovery code: **\(setup.revocationCode)**")
                        .font(.caption.weight(.medium))
                }
                .padding(8)
                .background(.red.opacity(0.04))
                .cornerRadius(6)
            }

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
        }
    }

    // MARK: - Helpers

    private func stepIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 36))
            .foregroundStyle(color)
    }

    private func progressView(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.2)
            Text(message).font(.subheadline).foregroundColor(.secondary)
        }
        .padding(.top, 40)
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Back")
                    .font(.caption.weight(.medium))
            }
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(setup.isWorking)
        .opacity(setup.isWorking ? 0.4 : 1)
    }

    @ViewBuilder
    private var inlineError: some View {
        if let error = setup.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text(error)
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: 360, alignment: .leading)
            .background(.orange.opacity(0.08))
            .cornerRadius(8)
        }
    }

    private func actionButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled || setup.isWorking)
        .frame(maxWidth: 280)
    }

    private var stepTitle: String {
        switch setup.step {
        case .login: return "Step 1 — Sign In"
        case .phoneSetup, .phoneEmailConfirmation, .phoneSMSVerify: return "Step 2 — Phone Setup"
        case .addingAuthenticator: return "Step 2 — Creating Authenticator"
        case .revocationCode: return "Step 3 — Recovery Code"
        case .finalizeSMS: return "Step 3 — Finalize"
        case .done: return "Complete"
        }
    }

    private var currentStepIndex: Int {
        switch setup.step {
        case .login: return 0
        case .phoneSetup, .phoneEmailConfirmation, .phoneSMSVerify: return 1
        case .addingAuthenticator, .revocationCode: return 2
        case .finalizeSMS: return 3
        case .done: return 3
        }
    }
}

// MARK: - Setup Steam Login (reuses the proven SteamLoginView pattern)

struct SetupSteamLoginView: View {
    let onLogin: ([HTTPCookie]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var currentURL = ""

    // Dummy account for the login view — we don't need auto-fill here
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text("Sign in to Steam")
                    .font(.headline)
                Spacer()

                if isLoading { ProgressView().scaleEffect(0.7) }

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

            // URL bar — live URL from WebView
            HStack(spacing: 6) {
                if currentURL.hasPrefix("https") {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
                Text(currentURL.isEmpty ? "Loading..." : currentURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05))

            Divider()

            SetupWebViewWrapper(isLoading: $isLoading, currentURL: $currentURL, onLogin: onLogin)
        }
        .frame(minWidth: 540, idealWidth: 560, minHeight: 580, idealHeight: 650)
    }
}

import WebKit

struct SetupWebViewWrapper: NSViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var currentURL: String
    let onLogin: ([HTTPCookie]) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = FocusableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        let url = URL(string: "https://steamcommunity.com/login/home/?goto=%2Fmy%2Fhome")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, currentURL: $currentURL, onLogin: onLogin)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        @Binding var currentURL: String
        let onLogin: ([HTTPCookie]) -> Void
        private var hasCompleted = false

        init(isLoading: Binding<Bool>, currentURL: Binding<String>, onLogin: @escaping ([HTTPCookie]) -> Void) {
            self._isLoading = isLoading
            self._currentURL = currentURL
            self.onLogin = onLogin
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               scheme != "https" && scheme != "http" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.isLoading = true
                self.currentURL = webView.url?.absoluteString ?? ""
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.currentURL = webView.url?.absoluteString ?? ""
            }
            startCookiePolling(webView: webView)
        }

        private func startCookiePolling(webView: WKWebView) {
            guard !hasCompleted else { return }
            var pollCount = 0
            func poll() {
                guard !self.hasCompleted, pollCount < 60 else { return }
                pollCount += 1
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self = self, !self.hasCompleted else { return }
                    let steamCookies = cookies.filter {
                        $0.domain.contains("steampowered.com") || $0.domain.contains("steamcommunity.com")
                    }
                    if steamCookies.contains(where: { $0.name == "steamLoginSecure" && !$0.value.isEmpty }) {
                        self.hasCompleted = true
                        DispatchQueue.main.async { self.onLogin(steamCookies) }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { poll() }
                    }
                }
            }
            poll()
        }
    }
}
