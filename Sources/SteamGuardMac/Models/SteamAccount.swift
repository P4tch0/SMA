import Foundation

/// A Steam account parsed from a steamguard-cli maFile. Supports SDA, steamguard-cli, and Android Steamguard JSON formats.
struct SteamAccount: Identifiable, Codable {
    var id: String { accountName }

    let sharedSecret: String
    let serialNumber: String?
    let revocationCode: String?
    let uri: String?
    let accountName: String
    let identitySecret: String?
    let deviceID: String?
    let steamID: UInt64?

    struct DynKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynKey.self)

        sharedSecret = try c.decode(String.self, forKey: DynKey(stringValue: "shared_secret")!)
        serialNumber = try c.decodeIfPresent(String.self, forKey: DynKey(stringValue: "serial_number")!)
        revocationCode = try c.decodeIfPresent(String.self, forKey: DynKey(stringValue: "revocation_code")!)
        uri = try c.decodeIfPresent(String.self, forKey: DynKey(stringValue: "uri")!)
        accountName = try c.decode(String.self, forKey: DynKey(stringValue: "account_name")!)
        identitySecret = try c.decodeIfPresent(String.self, forKey: DynKey(stringValue: "identity_secret")!)
        deviceID = try c.decodeIfPresent(String.self, forKey: DynKey(stringValue: "device_id")!)

        // steam_id can appear as "steam_id" (steamguard-cli), "steamid", or inside "Session.SteamID" (SDA)
        if let sid = try c.decodeIfPresent(UInt64.self, forKey: DynKey(stringValue: "steam_id")!) {
            steamID = sid
        } else if let sid = try c.decodeIfPresent(UInt64.self, forKey: DynKey(stringValue: "steamid")!) {
            steamID = sid
        } else if let sid = try c.decodeIfPresent(UInt64.self, forKey: DynKey(stringValue: "steamID")!) {
            steamID = sid
        } else {
            // Try Session.SteamID (original SDA format)
            struct Session: Codable {
                let SteamID: UInt64?
            }
            if let session = try c.decodeIfPresent(Session.self, forKey: DynKey(stringValue: "Session")!) {
                steamID = session.SteamID
            } else {
                steamID = nil
            }
        }
    }
}

struct ManifestEntry: Codable {
    let filename: String
    let steamid: UInt64?
}

struct Manifest: Codable {
    let entries: [ManifestEntry]
}
