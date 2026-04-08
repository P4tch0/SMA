import Foundation
import WebKit

struct TradeConfirmation: Identifiable {
    let id: String
    let key: String
    let type: Int
    let title: String
    let headline: String
    let description: String
    let summary: [String]
    let iconURL: String?
    let creatorID: String?
    let creationTime: UInt64?
    let acceptLabel: String
    let cancelLabel: String
}

struct PartnerInfo {
    let name: String
    let avatarURL: String?
    let level: Int
}

/// Fetches and manages Steam trade confirmations via the mobileconf API. Handles session refresh and time sync.
class TradeConfirmationManager: ObservableObject {
    @Published var confirmations: [TradeConfirmation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var needsLogin = false
    @Published var partnerInfo: [String: PartnerInfo] = [:]  // keyed by confirmation ID

    /// Ensures the access token is fresh. Returns valid cookies or nil if login is needed.
    /// If expired, loads steamcommunity.com in a hidden WebView to trigger Steam's JS auto-refresh.
    private func getValidCookies(for accountName: String) async -> [HTTPCookie]? {
        guard let cookies = KeychainHelper.loadSession(accountName: accountName) else {
            return nil
        }

        // Check if the token is still valid
        if let loginCookie = cookies.first(where: { $0.name == "steamLoginSecure" }),
           !TokenRefresher.isAccessTokenExpired(cookieValue: loginCookie.value) {
            return cookies
        }

        // Token expired — try silent refresh via WebView cookie injection
        if let refreshedCookies = await silentWebRefresh(accountName: accountName) {
            KeychainHelper.saveSession(accountName: accountName, cookies: refreshedCookies)
            return KeychainHelper.loadSession(accountName: accountName)
        }

        // Refresh failed — need full re-login
        return nil
    }

    /// Loads steamcommunity.com in a hidden non-persistent WebView with injected cookies.
    /// Steam's JS will refresh the access token automatically. Returns new cookies if successful.
    private func silentWebRefresh(accountName: String) async -> [HTTPCookie]? {
        guard let storedCookies = KeychainHelper.loadSession(accountName: accountName) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let helper = SilentRefreshHelper(cookies: storedCookies) { result in
                    continuation.resume(returning: result)
                }
                helper.start()
            }
        }
    }

    private func cookieHeader(from cookies: [HTTPCookie]) -> String {
        let communityCookies = cookies.filter { $0.domain.contains("steamcommunity.com") || $0.domain.hasPrefix(".") }
        let cookiesToUse = communityCookies.isEmpty ? cookies : communityCookies
        return cookiesToUse.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private var retryCount = 0

    func fetchConfirmations(for account: SteamAccount) async {
        retryCount = 0
        await doFetchConfirmations(for: account)
    }

    private func doFetchConfirmations(for account: SteamAccount) async {
        guard let identitySecret = account.identitySecret,
              let deviceID = account.deviceID,
              let steamID = account.steamID else {
            await MainActor.run { errorMessage = "Account missing identity_secret, device_id, or steam_id." }
            return
        }

        guard let cookies = await getValidCookies(for: account.accountName) else {
            await MainActor.run { needsLogin = true }
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
            statusMessage = nil
            needsLogin = false
        }

        await SteamTOTP.ensureSynced()
        let time = SteamTOTP.serverTime
        guard let confHash = SteamTOTP.generateConfirmationHash(identitySecret: identitySecret, time: time, tag: "conf") else {
            await MainActor.run { errorMessage = "Failed to generate confirmation hash."; isLoading = false }
            return
        }

        let encodedHash = confHash.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? confHash
        let encodedDeviceID = deviceID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceID

        let urlString = "https://steamcommunity.com/mobileconf/getlist?p=\(encodedDeviceID)&a=\(steamID)&k=\(encodedHash)&t=\(time)&m=android&tag=conf"

        guard let url = URL(string: urlString) else {
            await MainActor.run { errorMessage = "Invalid URL"; isLoading = false }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Linux; Android 9; Valve Steam App) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader(from: cookies), forHTTPHeaderField: "Cookie")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            if httpResponse?.statusCode == 401 || httpResponse?.statusCode == 403 {
                KeychainHelper.deleteSession(accountName: account.accountName)
                await MainActor.run { needsLogin = true; isLoading = false }
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "empty"
                await MainActor.run { errorMessage = "Unexpected response: \(bodyPreview)"; isLoading = false }
                return
            }

            let isSuccess: Bool
            if let b = json["success"] as? Bool { isSuccess = b }
            else if let n = json["success"] as? Int { isSuccess = n != 0 }
            else { isSuccess = false }

            if isSuccess {
                let confArray = json["conf"] as? [[String: Any]] ?? []
                let parsed = confArray.compactMap { item -> TradeConfirmation? in
                    let id: String
                    if let s = item["id"] as? String { id = s }
                    else if let n = item["id"] as? UInt64 { id = String(n) }
                    else if let n = item["id"] as? Int { id = String(n) }
                    else if let n = item["id"] as? NSNumber { id = n.stringValue }
                    else { return nil }

                    let key: String
                    if let s = item["nonce"] as? String { key = s }
                    else if let n = item["nonce"] as? UInt64 { key = String(n) }
                    else if let n = item["nonce"] as? Int { key = String(n) }
                    else if let n = item["nonce"] as? NSNumber { key = n.stringValue }
                    else { return nil }

                    let type = item["type"] as? Int ?? 0
                    let typeName = (item["type_name"] as? String) ?? "Confirmation"
                    let headline = (item["headline"] as? String) ?? ""
                    let summaryArr = (item["summary"] as? [String]) ?? []
                    let desc = headline.isEmpty ? summaryArr.joined(separator: " — ") : headline
                    let icon = item["icon"] as? String
                    let creatorID: String?
                    if let s = item["creator_id"] as? String { creatorID = s }
                    else if let n = item["creator_id"] as? UInt64 { creatorID = String(n) }
                    else { creatorID = nil }
                    let creationTime = item["creation_time"] as? UInt64
                    let acceptLabel = (item["accept"] as? String) ?? "Confirm"
                    let cancelLabel = (item["cancel"] as? String) ?? "Cancel"

                    return TradeConfirmation(
                        id: id, key: key, type: type, title: typeName,
                        headline: headline, description: desc, summary: summaryArr,
                        iconURL: icon, creatorID: creatorID, creationTime: creationTime,
                        acceptLabel: acceptLabel, cancelLabel: cancelLabel
                    )
                }

                await MainActor.run {
                    confirmations = parsed
                    statusMessage = parsed.isEmpty ? "No pending confirmations." : nil
                    isLoading = false
                }

                // Fetch partner info for each confirmation in background
                for conf in parsed {
                    Task { await self.fetchPartnerInfo(for: conf, account: account) }
                }
            } else {
                let needAuth = json["needsauth"] as? Bool ?? false
                let detail = json["detail"] as? String ?? json["message"] as? String

                if needAuth {
                    KeychainHelper.deleteSession(accountName: account.accountName)
                    await MainActor.run { needsLogin = true; isLoading = false }
                } else if retryCount < 2 {
                    // Likely a time sync issue — force re-sync and retry silently
                    retryCount += 1
                    await SteamTOTP.syncTime()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await doFetchConfirmations(for: account)
                } else {
                    await MainActor.run { errorMessage = detail ?? "Steam returned an error. Try logging in again."; isLoading = false }
                }
            }
        } catch {
            if retryCount < 2 {
                retryCount += 1
                await SteamTOTP.syncTime()
                try? await Task.sleep(nanoseconds: 500_000_000)
                await doFetchConfirmations(for: account)
            } else {
                await MainActor.run { errorMessage = "Network error: \(error.localizedDescription)"; isLoading = false }
            }
        }
    }

    /// Fetch partner info by loading the confirmation details and parsing the miniprofile ID
    private func fetchPartnerInfo(for confirmation: TradeConfirmation, account: SteamAccount) async {
        // Skip if already fetched
        if await MainActor.run(body: { partnerInfo[confirmation.id] }) != nil { return }

        guard let html = await fetchDetailsHTML(for: confirmation, account: account) else { return }

        // Parse data-miniprofile="accountID" from the HTML
        if let range = html.range(of: #"data-miniprofile="(\d+)""#, options: .regularExpression),
           let idRange = html[range].range(of: #"\d+"#, options: .regularExpression) {
            let accountID = String(html[idRange])

            // Fetch miniprofile JSON
            if let profile = await fetchMiniProfile(accountID: accountID) {
                await MainActor.run { partnerInfo[confirmation.id] = profile }
            }
        }
    }

    private func fetchMiniProfile(accountID: String) async -> PartnerInfo? {
        let urlString = "https://steamcommunity.com/miniprofile/\(accountID)/json"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let name = json["persona_name"] as? String ?? "Unknown"
            let avatar = json["avatar_url"] as? String
            let level = json["level"] as? Int ?? 0

            return PartnerInfo(name: name, avatarURL: avatar, level: level)
        } catch {
            return nil
        }
    }

    /// Fetch the details HTML for a confirmation
    func fetchDetailsHTML(for confirmation: TradeConfirmation, account: SteamAccount) async -> String? {
        guard let identitySecret = account.identitySecret,
              let deviceID = account.deviceID,
              let steamID = account.steamID,
              let cookies = await getValidCookies(for: account.accountName) else { return nil }

        await SteamTOTP.ensureSynced()
        let time = SteamTOTP.serverTime
        guard let confHash = SteamTOTP.generateConfirmationHash(identitySecret: identitySecret, time: time, tag: "detail") else { return nil }

        let encodedHash = confHash.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? confHash
        let encodedDeviceID = deviceID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceID

        let urlString = "https://steamcommunity.com/mobileconf/details/\(confirmation.id)?p=\(encodedDeviceID)&a=\(steamID)&k=\(encodedHash)&t=\(time)&m=android&tag=detail"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Linux; Android 9; Valve Steam App) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader(from: cookies), forHTTPHeaderField: "Cookie")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success,
               let html = json["html"] as? String {
                // Wrap in a full HTML page with Steam's CSS
                return """
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1">
                    <style>
                        body {
                            font-family: -apple-system, "Helvetica Neue", Arial, sans-serif;
                            margin: 0; padding: 16px;
                            background: #1b2838; color: #c6d4df;
                            font-size: 14px;
                        }
                        img { max-width: 100%; border-radius: 4px; }
                        .tradeoffer_items_banner { color: #8bc53f; font-weight: bold; margin: 8px 0; font-size: 13px; }
                        .tradeoffer_items { display: flex; flex-wrap: wrap; gap: 8px; margin: 8px 0; }
                        .trade_item { background: rgba(255,255,255,0.08); border-radius: 6px; padding: 4px; }
                        .tradeoffer_item_list { display: flex; flex-wrap: wrap; gap: 6px; }
                        a { color: #66c0f4; text-decoration: none; }
                        a:hover { text-decoration: underline; }
                        .mobileconf_trade_area { margin-bottom: 12px; }
                        .trade_partner_header { display: flex; align-items: center; gap: 10px; margin-bottom: 12px; }
                        .trade_partner_headline_sub { color: #8f98a0; font-size: 12px; }
                        .playerAvatar { border-radius: 4px; overflow: hidden; }
                        .playerAvatar img { width: 48px; height: 48px; }
                    </style>
                </head>
                <body>\(html)</body>
                </html>
                """
            }
            return nil
        } catch {
            return nil
        }
    }

    func respondToConfirmation(_ confirmation: TradeConfirmation, accept: Bool, account: SteamAccount, retryAttempt: Int = 0) async {
        guard let identitySecret = account.identitySecret,
              let deviceID = account.deviceID,
              let steamID = account.steamID,
              let cookies = await getValidCookies(for: account.accountName) else { return }

        let tag = accept ? "allow" : "cancel"
        // Force fresh time sync on every attempt
        await SteamTOTP.syncTime()
        let time = SteamTOTP.serverTime
        guard let confHash = SteamTOTP.generateConfirmationHash(identitySecret: identitySecret, time: time, tag: tag) else { return }

        let op = accept ? "allow" : "cancel"
        let encodedHash = confHash.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? confHash
        let encodedDeviceID = deviceID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceID

        let urlString = "https://steamcommunity.com/mobileconf/ajaxop?op=\(op)&p=\(encodedDeviceID)&a=\(steamID)&k=\(encodedHash)&t=\(time)&m=android&tag=\(tag)&cid=\(confirmation.id)&ck=\(confirmation.key)"

        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Linux; Android 9; Valve Steam App) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader(from: cookies), forHTTPHeaderField: "Cookie")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let success: Bool
                if let b = json["success"] as? Bool { success = b }
                else if let n = json["success"] as? Int { success = n != 0 }
                else { success = false }

                if success {
                    await MainActor.run {
                        confirmations.removeAll { $0.id == confirmation.id }
                        statusMessage = accept ? "Confirmation accepted!" : "Confirmation denied."
                    }
                } else if retryAttempt < 2 {
                    // Retry with fresh time sync — likely a stale confirmation hash
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await respondToConfirmation(confirmation, accept: accept, account: account, retryAttempt: retryAttempt + 1)
                } else {
                    let detail = json["detail"] as? String ?? json["message"] as? String ?? "Unknown error"
                    await MainActor.run { errorMessage = "Failed: \(detail) (HTTP \(httpStatus))" }
                }
            } else {
                let body = String(data: data.prefix(200), encoding: .utf8) ?? "empty"
                await MainActor.run { errorMessage = "Failed (HTTP \(httpStatus)): \(body)" }
            }
        } catch {
            await MainActor.run { errorMessage = "Network error: \(error.localizedDescription)" }
        }
    }
}

// MARK: - Silent Refresh Helper

/// Holds a non-persistent WKWebView strongly while it loads steamcommunity.com
/// with injected cookies to trigger Steam's JS token refresh.
private class SilentRefreshHelper: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private let cookies: [HTTPCookie]
    private let completion: ([HTTPCookie]?) -> Void
    private var hasCompleted = false

    init(cookies: [HTTPCookie], completion: @escaping ([HTTPCookie]?) -> Void) {
        self.cookies = cookies
        self.completion = completion
        super.init()
    }

    func start() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        // Inject the stored cookies into the non-persistent store, then load the page
        let cookieStore = config.websiteDataStore.httpCookieStore
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) {
            guard let url = URL(string: "https://steamcommunity.com/my/home") else {
                self.finish(nil)
                return
            }
            wv.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait 2 seconds for Steam's JS to refresh the token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.extractCookies()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    private func extractCookies() {
        guard let wv = webView else { finish(nil); return }

        wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] allCookies in
            guard let self = self else { return }

            let steamCookies = allCookies.filter {
                ($0.domain.contains("steampowered.com") || $0.domain.contains("steamcommunity.com")) &&
                (["steamLoginSecure", "sessionid"].contains($0.name) || $0.name.starts(with: "steamMachineAuth")) &&
                !$0.value.isEmpty
            }

            let hasValidToken = steamCookies.contains { cookie in
                cookie.name == "steamLoginSecure" &&
                !TokenRefresher.isAccessTokenExpired(cookieValue: cookie.value)
            }

            self.finish(hasValidToken ? steamCookies : nil)
        }
    }

    private func finish(_ result: [HTTPCookie]?) {
        guard !hasCompleted else { return }
        hasCompleted = true
        webView?.navigationDelegate = nil
        webView = nil
        completion(result)
    }
}

