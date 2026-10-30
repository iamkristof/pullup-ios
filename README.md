# Pullup for iOS

Native SwiftUI attendee app for iOS 17+. Guest discovery, email sign-in and sign-up, location-approval and authenticator challenges, a personal ticket wallet, rotating door QR, and native Apple Wallet presentation. Dark surfaces, acid-green accents, adaptive layouts, Dynamic Type and spring button interactions. No third-party app SDKs or embedded service keys.

## Open in Xcode

1. Install Xcode on your Mac and open it once. Install an iOS simulator when prompted.
2. Clone this repository. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) with `brew install xcodegen`.
3. In this folder run `xcodegen generate`, then open `Pullup.xcodeproj`.
4. Select the Pullup scheme and an iPhone simulator. Press Run.
5. For your iPhone, select team `9Z686XN9U2` in Signing & Capabilities. Register bundle ID `at.pullup.ios` if needed. Enable automatic signing, select the device and Run.

No p12, Stripe, Supabase or Resend secrets belong in this repository. Wallet passes are signed by the existing website.

## Backend dependency — deploy before testing tickets

The companion web change adds `GET /api/mobile/tickets` to `iamkristof/pullup`. Merge/deploy that change first. No migration or new environment variable is required. Browse and auth use the existing website APIs; nothing calls the old `/api/app` endpoints.

| App feature | Existing web route |
| --- | --- |
| Public events, search and paging | `/api/events/browse` |
| Login and signup | `/api/auth/login`, `/api/auth/signup` |
| Login approval and 2FA | `/api/auth/login-challenge`, `/api/auth/2fa/login-verify` |
| Account and logout | `/api/auth/me`, `/api/auth/logout` |
| Account ticket list | `/api/mobile/tickets` (new) |
| Ticket state and entry details | `/api/ticket/{reference}` |
| Rotating QR | `/api/qr/generate` |
| Signed Apple Wallet pass | `/api/ticket/{reference}/apple-wallet` |

Event details/checkout, guest-email ticket recovery, settings and full ticket extras use the current website in an isolated WebKit sheet. This preserves queue, payment, bank-transfer, instalment and add-on behaviour. Native checkout does not recreate those rules. WebKit imports the authenticated session; it does not put credentials in URLs. External HTTPS payment redirects remain supported.

Sessions are stored in device-only, unlocked Keychain storage. API responses and ticket QR data are not cached to disk. Passwords are held only for the current auth flow. App-switcher content is concealed. QR disappears when expired/backgrounded or when refresh fails. Entry eligibility remains enforced by the server scanner. The app displays no fabricated offline QR.

The new wallet endpoint only matches an email when the account email is verified. Unverified users see explicitly linked tickets and can use the existing guest email-verification flow. Reads never claim or reassign tickets. It paginates in stable 40-row pages and omits venue addresses from the list; the ticket detail endpoint governs location access.

## Validation and release

GitHub Actions generates the project and builds/runs unit tests on an iOS simulator without certificates. See Actions for actual results; local Linux cannot run Xcode. Do not treat this repository as a tested TestFlight build until CI and physical-device checks pass.

Before TestFlight:
- Verify guest browsing, search, empty/error/retry and pagination.
- Check signup verification email, existing sign-in, location approval, 2FA, expired session and logout.
- On a test event check native tickets, entry time, pending bank approval, cancelled/refunded tickets, check-in, QR rotation and native Wallet on a physical iPhone.
- Check card/3DS and bank checkout through WebKit with test credentials; never use real customer cards for QA.
- Review privacy disclosures in App Store Connect. Accounts are managed by Pullup; account deletion is reachable in website settings inside the app. Confirm the complete deletion flow before submission.
- Add the approved current Pullup app icon (1024px) and screenshots. No old logo has been substituted.
- Confirm in-app purchase rules for any digital memberships exposed by linked website pages before App Store submission. This first version sells real-world event tickets through the existing checkout; it has no native subscription purchase flow.

Create a new iOS app in App Store Connect using `at.pullup.ios`. In Xcode choose a generic iOS device, Product → Archive → Distribute App → App Store Connect. Complete TestFlight metadata and testing before App Review. Apple Developer membership alone does not publish an app.

## Current scope

Native: discover, auth, account summary, ticket list/detail, QR, Apple Wallet. Web-backed: event checkout, ticket extras/bar passes, guest recovery and settings. Push notifications, universal links, offline ticket storage, native Google/Apple login and host tools are not implemented in this version. Passwordless/Google-only accounts can use the website sign-in flow from account settings once a dedicated native OAuth callback is added; do not embed provider secrets or bypass existing security checks.
