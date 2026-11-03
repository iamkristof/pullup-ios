# Test Pullup on your MacBook

You do not need an iPhone, signing certificate, terminal command or paid provisioning profile to use the iPhone Simulator.

## First run

1. Install [Xcode](https://apps.apple.com/app/xcode/id497799835) on your Mac. Open it once, accept the licence and install an iOS Simulator runtime when prompted. If prompted later, install one in Xcode → Settings → Components.
2. Download this branch using GitHub **Code → Download ZIP**, then unzip it. Until the app PR is merged, use the `codex/native-ios-app` branch.
3. Double-click **Pullup.xcodeproj**. The project is included; no Homebrew or XcodeGen setup is required for running it.
4. At the top of Xcode, select the **Pullup Auth Preview** scheme and an **iPhone simulator**. Do not choose “Any iOS Device” or your Mac as the destination.
5. Press **⌘R**. The iPhone Simulator opens on your MacBook with the new welcome screen.

For the newest native Liquid Glass, use Xcode 26 or newer and an iOS 26+ simulator. The app still runs on iOS 17+ with an accessible frosted-material fallback. Use an Xcode version supported by your macOS; Xcode will tell you if your Mac needs updating.

## Preview safely without real accounts

**Pullup Auth Preview** uses an isolated DEBUG-only fixture service. You can walk through sign-in or create an account using `alex@example.com` and any password of at least eight characters. Signup requires matching email addresses, a name and acceptance of the terms. No account is created, no verification email is sent and no preview credentials are stored in Keychain.

To try other screens: Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables → change `AUTH_SCENARIO` to:

| Value | Preview |
| --- | --- |
| `success` | Normal sign-in/signup and success |
| `error` | Wrong-credentials message and editable retry |
| `approval` | Location approval email with authenticator alternative |
| `twoFactor` | Authenticator / backup-code entry |

Preview transport does not exist in Release builds. The normal scheme uses the live Pullup backend.

## Test your real Pullup account

1. Stop the app with **⌘.**.
2. Select the **Pullup** scheme and the same iPhone simulator, then **⌘R**.
3. Open **You → Sign in or create account** (or **Tickets → Sign in**).
4. Use your real Pullup email/password. New-location approval and 2FA still apply. New account creation here creates a real account and sends the normal verification email.

The ticket-list web integration must be deployed for the native wallet. Authentication itself uses the existing `/api/auth` endpoints and does not require new SQL, secrets or backend changes.

## Xcode canvas and tests

- Open `Pullup/AuthPreviews.swift`, choose Editor → Canvas, then Resume for native SwiftUI previews.
- Press **⌘U** in the Pullup scheme to run the unit and UI tests. Auth UI tests use fixtures; they do not create accounts or call the live auth backend.
- GitHub Actions runs those tests and saves screenshots of welcome, signup, sign-in, errors, location approval, 2FA and success in its test-results artifact.
- Use Simulator → Device → Rotate to check landscape, and Settings → Accessibility to check larger text, Reduce Motion and Reduce Transparency.

## On your iPhone later

Select the Pullup target → Signing & Capabilities → your team `9Z686XN9U2`. Enable automatic signing, select your connected iPhone and Run. The simulator does not need those signing steps. Test actual account verification, password autofill, Wallet and payments on a physical device before TestFlight.
