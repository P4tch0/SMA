# SMA — Steam Mac Authenticator

A native macOS app for Steam Guard 2FA codes and trade confirmations. Built with SwiftUI, no external dependencies.

**The first fully-featured Steam Desktop Authenticator for Mac.**

<p align="center">
  <img src="screenshots/main.png" alt="SMA Main Screen" width="520">
</p>

---

## Features

- **Live 2FA codes** — Auto-refreshing codes for all your accounts, synced to Steam server time
- **Trade confirmations** — View, accept, and deny trades with partner details (avatar, name, Steam level)
- **Add Steam Guard** — Set up a new authenticator directly from the app
- **Import maFile** — Drag & drop maFiles from SDA, steamguard-cli, or Android backups. Handles SDA-encrypted files
- **Auto-fill login** — Username pre-filled and locked, 2FA code auto-entered during Steam login
- **Update notifications** — Checks GitHub for new releases on launch
- **Session persistence** — Log in once, stay logged in via auto-refreshing tokens
- **Encrypted storage** — Sessions encrypted with AES-256-GCM using a random key
- **No telemetry** — No analytics, no tracking. All traffic goes to Steam's servers only
- **No dependencies** — Only Apple system frameworks. Nothing external.

## Install

### Build from source (recommended)

Building from source lets you verify exactly what you're running:

```bash
git clone https://github.com/P4tch0/SMA.git
cd SMA
swift build -c release
# Binary at .build/release/SteamGuardMac
```

### Download DMG

Releases are built automatically by [GitHub Actions](../../actions) from the source code in this repo.

1. Download `SMA-v1.0.0.dmg` from [Releases](../../releases)
2. Open the DMG and drag **Steam Mac Authenticator** to Applications
3. First launch: right-click the app → **Open** → **Open** (one-time macOS prompt for unsigned apps)
4. Optionally verify the hash: `shasum -a 256 SMA-v1.0.0.dmg`

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon or Intel Mac

## How it works

SMA uses Steam Guard secrets in the standard maFile format (same as SDA and steamguard-cli).

- **Import existing maFiles** — Drag them in. If they're SDA-encrypted, the app will ask for your passkey.
- **Add new Steam Guard** — Sign in through Steam's web login inside the app. SMA handles phone verification, SMS codes, and authenticator setup.

All network traffic goes to `api.steampowered.com` and `steamcommunity.com`. The app doesn't contact any other server.

## Security

### What's in place

| Area | Detail |
|------|--------|
| Encryption | AES-256-GCM with a randomly generated 256-bit key |
| Key storage | Stored locally with 0600 file permissions (owner-only) |
| Tokens | Kept in encrypted files — never written to plaintext maFiles |
| Network | HTTPS only. Tokens sent in POST body, not URL parameters |
| WebView | Non-persistent cookie store. Custom URL schemes blocked |
| Input handling | User input escaped before JavaScript injection |
| Logging | Debug-only (`#if DEBUG`). No sensitive data in production logs |
| Concurrency | Time sync state protected by NSLock |
| Dependencies | Zero. No third-party packages. |

### Threat model

SMA protects against:
- Plaintext secret storage on disk
- Token leakage via URLs or logs
- Cross-site scripting in the login WebView
- Expired sessions (auto-refreshes transparently)

SMA does not protect against:
- A compromised Mac (malware with disk access can read anything)
- Physical access to an unlocked machine
- Keyloggers or screen capture malware
- A revoked or leaked maFile

If your machine is compromised, no authenticator app can help — that applies to SDA, Steam mobile, and SMA equally.

## Privacy

- SMA never stores your Steam password. Login happens on Steam's official site via an in-app WebView.
- No telemetry, no analytics, no crash reporting. The only network calls go to Steam.
- No auto-updates. The app checks GitHub for new releases and shows a notification — you decide when to update.
- Source code is available here for review.

## Transparency

| Question | Answer |
|----------|--------|
| Where does the DMG come from? | Built by [GitHub Actions](../../actions) from this source code. Not uploaded manually. |
| Why no code signing? | An Apple Developer certificate is required, which isn't currently set up. Building from source avoids Gatekeeper entirely. |
| Where does network traffic go? | Only `steampowered.com` and `steamcommunity.com`. |
| Any external dependencies? | None. `Package.swift` has zero packages. |

## Supported Formats

| Format | Source |
|--------|--------|
| `.maFile` | SDA / steamguard-cli |
| `Steamguard-*` | Android Steam app (rooted backup) |
| `.json` | Any JSON export containing `shared_secret` |
| SDA encrypted | Supported — app asks for your passkey and decrypts |

## Tech Stack

- Swift / SwiftUI
- macOS 13+
- CryptoKit (AES-256-GCM)
- CommonCrypto (HMAC-SHA1 for TOTP)
- WebKit (Steam login WebView)
- Security framework (RSA encryption)

## FAQ

**Will this trigger a 15-day trade hold?**
Not if you import an existing maFile. The authenticator stays on your phone — SMA generates the same codes from the same secret. Only the "Add Steam Guard" flow involves changing the authenticator.

**Why does macOS say "unidentified developer"?**
The app isn't signed with an Apple Developer certificate. Right-click → Open → Open bypasses this on first launch.

**Is this safe?**
The source code is public. There are no external dependencies and no network calls outside Steam. Review the code or build from source if you want to verify.

## Contact

- Steam: [Patcho](https://steamcommunity.com/id/Patcho)
- Telegram: [@Yazan](https://t.me/Yazan)
- Twitter: [@PatchoCSGO](https://x.com/PatchoCSGO)

Found a bug or have a suggestion? Open an [issue](../../issues) or reach out above.

## Disclaimer

Not affiliated with Valve Corporation. Steam is a trademark of Valve Corporation. SMA uses Steam's public web APIs and login pages — the same mechanisms used by your browser. Use at your own risk.

## License

MIT License. See [LICENSE](LICENSE) for details.
