# SMA — Steam Mac Authenticator

A native macOS app for Steam Guard 2FA codes and trade confirmations. Built with SwiftUI, no external dependencies.

**The first fully-featured Steam Desktop Authenticator for Mac.**

---

## Features

- **Live 2FA codes** — All your Steam accounts with auto-refreshing codes, synced to Steam's server time
- **Trade confirmations** — View, accept, and deny trades with partner details (avatar, name, Steam level)
- **Add Steam Guard** — Set up authenticator on new accounts directly from the app
- **Import maFile** — Drag & drop existing maFiles from SDA, steamguard-cli, or Android backups
- **Auto-fill login** — Username locked + 2FA code auto-filled when signing in to Steam
- **Session persistence** — Login once, stay logged in for months (auto-refresh tokens)
- **Encrypted storage** — Sessions encrypted with AES-256-GCM, random key, owner-only file permissions
- **Zero telemetry** — No analytics, no tracking, no phone-home. Talks to Steam servers only.
- **No dependencies** — Fully self-contained. Nothing to install.

## Install

### Download (recommended)

1. Download `SMA-v1.0.0.dmg` from [Releases](../../releases)
2. Open the DMG and drag **Steam Mac Authenticator** to Applications
3. First launch: right-click the app → **Open** → **Open** (one-time macOS unsigned app prompt)

### Build from source

```bash
git clone https://github.com/P4tch0/SMA.git
cd SMA
swift build -c release
```

Binary will be at `.build/release/SteamGuardMac`.

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon or Intel Mac

## How it works

SMA reads Steam Guard secrets from steamguard-cli's maFile format. You can:

1. **Import existing maFiles** — If you have maFiles from SDA or another tool, just drag them into the app
2. **Add new Steam Guard** — Sign in via Steam's web login, and SMA handles the full authenticator setup (phone verification, SMS code, etc.)

All communication goes directly to Steam's servers (`api.steampowered.com`, `steamcommunity.com`). Nothing is sent anywhere else.

## Security

| Feature | Detail |
|---------|--------|
| Encryption | AES-256-GCM with random 256-bit key |
| Key storage | Random key file with 0600 permissions (owner-only) |
| Tokens | Stored in encrypted files, never in plaintext maFiles |
| Network | HTTPS only, tokens in POST body (not URL params) |
| WebView | Non-persistent cookie store, steammobile:// blocked |
| JS injection | User input escaped against XSS (quotes, HTML, backslash) |
| Logging | Debug-only (`#if DEBUG`), no sensitive data logged |
| Thread safety | Time sync state protected by NSLock |
| Dependencies | Zero. No third-party code. No supply chain risk. |

## Privacy

- SMA **never stores your Steam password**. Login happens on Steam's official website via an in-app WebView.
- **No telemetry, no analytics, no crash reporting.** The app never phones home.
- **No auto-updates.** You control when to update.
- All network traffic goes to Steam and nowhere else.
- Full source code available for review.

## Tech Stack

- Swift / SwiftUI
- macOS 13+
- CryptoKit (AES-256-GCM)
- CommonCrypto (HMAC-SHA1 for TOTP)
- WebKit (Steam login WebView)
- Security framework (RSA encryption)
- Zero external packages

## Supported Formats

| Format | Source |
|--------|--------|
| `.maFile` | SDA / steamguard-cli |
| `Steamguard-*` | Android Steam app (rooted backup) |
| `.json` | Any JSON export with `shared_secret` |

## FAQ

**Q: Will this trigger a 15-day trade hold?**
A: Not if you import an existing maFile. The authenticator stays active on your phone — SMA just clones the codes. Only the "Add Steam Guard" flow (new setup) involves removing/adding.

**Q: Why does macOS say "unidentified developer"?**
A: The app isn't code-signed with an Apple Developer certificate. Right-click → Open → Open bypasses this. It only happens once.

**Q: Is this safe?**
A: The full source code is here. No external dependencies. Security-audited. Read it yourself.

## Contact

- Steam: [Patcho](https://steamcommunity.com/id/Patcho)
- Telegram: [@Yazan](https://t.me/Yazan)
- Twitter: [@PatchoCSGO](https://x.com/PatchoCSGO)

Found a bug or have a suggestion? Open an [issue](../../issues) or reach out on any platform above.

## License

MIT License. See [LICENSE](LICENSE) for details.

---

*Not affiliated with Valve Corporation. Steam is a trademark of Valve Corporation.*
