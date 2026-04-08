import SwiftUI
import WebKit

struct SteamLoginView: View {
    let account: SteamAccount
    let onLoginSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    // Show disclaimer only on first ever login — skip on re-login
    @State private var showDisclaimer = !UserDefaults.standard.bool(forKey: "sma_disclaimer_accepted")
    @State private var isLoading = true
    @State private var currentURL = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Steam Login")
                        .font(.headline)
                    Text(account.accountName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                if isLoading && !showDisclaimer {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding()
            .background(.bar)

            // URL bar — live URL
            if !showDisclaimer {
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
            }

            Divider()

            // Tip banner
            if !showDisclaimer {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    Text("Steam asks to confirm via mobile app? Click **\"Enter code instead\"** — SMA will auto-fill it for you.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.04))
            }

            if showDisclaimer {
                disclaimerView
            } else {
                SteamWebView(
                    accountName: account.accountName,
                    sharedSecret: account.sharedSecret,
                    isLoading: $isLoading,
                    currentURL: $currentURL,
                    onLoginSuccess: {
                        onLoginSuccess()
                        dismiss()
                    }
                )
            }
        }
        .frame(minWidth: 500, idealWidth: 520, minHeight: 550, idealHeight: 600)
    }

    private var disclaimerView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "info.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Privacy Notice")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                disclaimerRow(icon: "globe", text: "You are about to log in directly to **Steam's official website** (steamcommunity.com). Your credentials are sent to Valve's servers only.")

                disclaimerRow(icon: "lock.fill", text: "Your session cookies are stored **locally with AES-256-GCM encryption**. Only this app on your Mac user account can decrypt them.")

                disclaimerRow(icon: "eye.slash.fill", text: "This app **never sees, stores, or transmits your password**. The login happens entirely within Steam's web page.")

                disclaimerRow(icon: "server.rack", text: "**No data is sent to any third-party server.** All communication is between this app and Steam only.")

                disclaimerRow(icon: "trash.fill", text: "You can log out at any time, which deletes the stored session.")
            }
            .padding(.horizontal, 30)

            Spacer()

            Button {
                UserDefaults.standard.set(true, forKey: "sma_disclaimer_accepted")
                withAnimation { showDisclaimer = false }
            } label: {
                Text("Continue to Steam Login")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    private func disclaimerRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)
            Text(text)
                .font(.callout)
                .foregroundColor(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Focusable WKWebView subclass

class FocusableWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }
}

// MARK: - WKWebView wrapper

struct SteamWebView: NSViewRepresentable {
    let accountName: String
    let sharedSecret: String
    @Binding var isLoading: Bool
    @Binding var currentURL: String
    let onLoginSuccess: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Use non-persistent for login (fresh session each time, no cross-account bleed)
        // After login, cookies are copied to the persistent store for silent refresh
        config.websiteDataStore = .nonPersistent()

        let webView = FocusableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        // Login via steamcommunity.com so cookies are on the right domain for confirmations API
        let url = URL(string: "https://steamcommunity.com/login/home/?goto=%2Fmy%2Fhome")!
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(accountName: accountName, sharedSecret: sharedSecret, isLoading: $isLoading, currentURL: $currentURL, onLoginSuccess: onLoginSuccess)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let accountName: String
        let sharedSecret: String
        @Binding var isLoading: Bool
        @Binding var currentURL: String
        let onLoginSuccess: () -> Void
        private var hasCompleted = false

        init(accountName: String, sharedSecret: String, isLoading: Binding<Bool>, currentURL: Binding<String>, onLoginSuccess: @escaping () -> Void) {
            self.accountName = accountName
            self.sharedSecret = sharedSecret
            self._isLoading = isLoading
            self._currentURL = currentURL
            self.onLoginSuccess = onLoginSuccess
        }

        // Block non-HTTP schemes like steammobile://, steam://, etc.
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
            injectCodeWatcher(webView: webView)
            startCookiePolling(webView: webView)
        }

        private func injectCodeWatcher(webView: WKWebView) {
            // Escape username for safe JavaScript string embedding (prevents XSS/injection)
            let safeUsername = accountName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "<", with: "\\x3C")
                .replacingOccurrences(of: ">", with: "\\x3E")
            let js = """
            (function() {
                if (window.__smaWatcherActive) return;
                window.__smaWatcherActive = true;

                var username = '\(safeUsername)';

                function fillUsername() {
                    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;

                    // Try all known selectors
                    var candidates = [
                        document.querySelector('input[name="username"]'),
                        document.querySelector('#input_username'),
                        document.querySelector('form[name="logon"] input[name="username"]'),
                    ];

                    // Also find any text input that appears before a password input
                    var allInputs = document.querySelectorAll('input');
                    var foundPassword = false;
                    for (var i = 0; i < allInputs.length; i++) {
                        if (allInputs[i].type === 'password') { foundPassword = true; break; }
                        if ((allInputs[i].type === 'text' || allInputs[i].type === '') &&
                            allInputs[i].maxLength !== 1 &&
                            allInputs[i].offsetParent !== null) {
                            candidates.push(allInputs[i]);
                        }
                    }

                    for (var j = 0; j < candidates.length; j++) {
                        var el = candidates[j];
                        if (el && el.offsetParent !== null) {
                            setter.call(el, username);
                            el.dispatchEvent(new Event('input', { bubbles: true }));
                            el.dispatchEvent(new Event('change', { bubbles: true }));
                            el.dispatchEvent(new Event('blur', { bubbles: true }));
                            el.readOnly = true;
                            el.style.opacity = '0.7';
                            el.style.pointerEvents = 'none';
                            return true;
                        }
                    }

                    return false;
                }

                function findCodeField() {
                    var oldInput = document.querySelector('#twofactorcode_entry') ||
                                   document.querySelector('#authcode') ||
                                   document.querySelector('input.twofactorauthcode_entry_input') ||
                                   document.querySelector('input.authcode_entry_input');
                    if (oldInput && oldInput.offsetParent !== null) return { type: 'single', el: oldInput };

                    var digitInputs = document.querySelectorAll('input[type="text"][maxlength="1"]');
                    if (digitInputs.length >= 5) return { type: 'multi', els: digitInputs };

                    var generic = document.querySelector('input[placeholder*="code" i]') ||
                                  document.querySelector('input[name="authcode"]');
                    if (generic && generic.offsetParent !== null) return { type: 'single', el: generic };

                    return null;
                }

                function fillField(field, code) {
                    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
                    if (field.type === 'single') {
                        setter.call(field.el, code);
                        field.el.dispatchEvent(new Event('input', { bubbles: true }));
                        field.el.dispatchEvent(new Event('change', { bubbles: true }));
                        field.el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
                    } else if (field.type === 'multi') {
                        for (var i = 0; i < Math.min(code.length, field.els.length); i++) {
                            setter.call(field.els[i], code[i]);
                            field.els[i].dispatchEvent(new Event('input', { bubbles: true }));
                            field.els[i].dispatchEvent(new Event('change', { bubbles: true }));
                            field.els[i].dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: code[i] }));
                        }
                    }
                }

                window.__smaFillCode = function(code) {
                    var field = findCodeField();
                    if (field) fillField(field, code);
                };

                // Try to fill username immediately and watch for DOM changes
                var usernameFilled = fillUsername();
                var codeFound = false;
                var attempts = 0;
                var poller = setInterval(function() {
                    attempts++;
                    if (!usernameFilled) usernameFilled = fillUsername();
                    if (!codeFound) {
                        var field = findCodeField();
                        if (field) {
                            codeFound = true;
                            clearInterval(poller);
                            document.title = '__SMA_NEEDS_CODE__';
                        }
                    }
                    if (attempts > 120) clearInterval(poller);
                }, 500);
            })();
            """

            webView.evaluateJavaScript(js) { _, _ in }
            webView.addObserver(self, forKeyPath: "title", options: .new, context: nil)
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            guard keyPath == "title",
                  let webView = object as? WKWebView,
                  let title = change?[.newKey] as? String,
                  title == "__SMA_NEEDS_CODE__" else { return }

            // Sync time then generate a fresh code
            Task {
                await SteamTOTP.ensureSynced()
                let code = SteamTOTP.generateCode(sharedSecret: self.sharedSecret)
                await MainActor.run {
                    let js = "if (window.__smaFillCode) window.__smaFillCode('\(code)');"
                    webView.evaluateJavaScript(js) { _, _ in }
                    webView.evaluateJavaScript("document.title = 'Steam Login';") { _, _ in }
                }
            }
        }

        private func startCookiePolling(webView: WKWebView) {
            guard !hasCompleted else { return }
            var pollCount = 0
            func poll() {
                guard !self.hasCompleted, pollCount < 40 else { return }
                pollCount += 1
                self.checkForLoginCookies(webView: webView)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { poll() }
            }
            poll()
        }

        private func checkForLoginCookies(webView: WKWebView) {
            guard !hasCompleted else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.hasCompleted else { return }

                let allSteamCookies = cookies.filter {
                    $0.domain.contains("steampowered.com") || $0.domain.contains("steamcommunity.com")
                }
                let hasLoginSecure = allSteamCookies.contains {
                    $0.name == "steamLoginSecure" && !$0.value.isEmpty
                }

                if hasLoginSecure {
                    self.hasCompleted = true

                    // Save session cookies for API calls
                    let relevantCookies = allSteamCookies.filter {
                        ["steamLoginSecure", "sessionid"].contains($0.name) ||
                        $0.name.starts(with: "steamMachineAuth")
                    }
                    KeychainHelper.saveSession(accountName: self.accountName, cookies: relevantCookies)

                    DispatchQueue.main.async {
                        self.onLoginSuccess()
                    }
                }
            }
        }
    }
}
