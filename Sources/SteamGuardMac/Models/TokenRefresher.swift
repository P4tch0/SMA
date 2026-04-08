import Foundation

/// Handles JWT access token decoding, expiry checking, and refresh via Steam's API.
enum TokenRefresher {

    /// Decode a JWT payload (no signature verification — we just need the `exp` claim)
    static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
        // Pad to multiple of 4
        while base64.count % 4 != 0 { base64.append("=") }
        // URL-safe base64 → standard base64
        base64 = base64.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Extract the access token JWT from a steamLoginSecure cookie value
    /// Format: steamID%7C%7CeyJ... or steamID||eyJ...
    static func extractAccessToken(from cookieValue: String) -> String? {
        let decoded = cookieValue.removingPercentEncoding ?? cookieValue
        let parts = decoded.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        // Format: steamID||JWT
        if parts.count >= 3 {
            return String(parts[2])
        }
        // Try splitting on %7C%7C directly
        if let range = cookieValue.range(of: "%7C%7C") {
            return String(cookieValue[range.upperBound...])
        }
        return nil
    }

    /// Check if a steamLoginSecure cookie's access token is expired (or will expire within 5 minutes)
    static func isAccessTokenExpired(cookieValue: String) -> Bool {
        guard let jwt = extractAccessToken(from: cookieValue),
              let payload = decodeJWTPayload(jwt),
              let exp = payload["exp"] as? Double else {
            return true // If we can't decode, assume expired
        }
        // Expired if less than 5 minutes remaining
        return Date().timeIntervalSince1970 > (exp - 300)
    }

    /// Extract steamID from a steamLoginSecure cookie value
    static func extractSteamID(from cookieValue: String) -> String? {
        let decoded = cookieValue.removingPercentEncoding ?? cookieValue
        let parts = decoded.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty else { return nil }
        return String(first)
    }

    /// Refresh the access token using the refresh token
    /// Returns the new steamLoginSecure cookie value, or nil on failure
    static func refreshAccessToken(refreshToken: String, steamID: String) async -> String? {
        let urlString = "https://api.steampowered.com/IAuthenticationService/GenerateAccessTokenForApp/v1/"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "refresh_token=\(refreshToken)&steamid=\(steamID)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseObj = json["response"] as? [String: Any],
                  let newAccessToken = responseObj["access_token"] as? String else {
                return nil
            }

            // Reconstruct the steamLoginSecure value
            let encodedSteamID = steamID
            return "\(encodedSteamID)%7C%7C\(newAccessToken)"
        } catch {
            return nil
        }
    }
}
