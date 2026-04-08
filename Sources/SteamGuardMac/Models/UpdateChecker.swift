import Foundation

/// Checks GitHub releases for new versions. No auto-update — just notifies the user.
class UpdateChecker: ObservableObject {
    @Published var newVersion: String?
    @Published var releaseURL: URL?

    private static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private static let repoAPI = "https://api.github.com/repos/P4tch0/SMA/releases/latest"

    func checkForUpdate() async {
        guard let url = URL(string: Self.repoAPI) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            // Strip "v" prefix: "v1.1.0" → "1.1.0"
            let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if Self.isNewer(latest, than: Self.currentVersion) {
                await MainActor.run {
                    newVersion = latest
                    releaseURL = URL(string: htmlURL)
                }
            }
        } catch {}
    }

    /// Compare semver strings: "1.1.0" > "1.0.0"
    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
