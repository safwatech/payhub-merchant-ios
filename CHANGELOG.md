# Changelog

All notable changes to **PayHub Merchant** (iOS) are documented here. This
project follows [Semantic Versioning](https://semver.org/).

## [0.4.0] — 2026-05-14

The 1.2.0 SDK uplift — every `/merchant/*` endpoint now rides the SDK — plus
four feature follow-ups that round out the on-device parent-OWNER toolkit.
Mirrors the Android 0.4.0 slice.

### Added
- **Universal Links for the invite URL.** `https://app.payhub.ly/m/accept-invite?…`
  now opens the app directly on devices where it's installed (verified via the
  `applinks:app.payhub.ly` Associated Domain against the server-side
  `/.well-known/apple-app-site-association`). The legacy `payhub://accept-invite`
  custom-scheme URL Type is kept through this release for in-flight emails —
  slated for removal in 0.5.0.
- **More → Diagnostics** screen with a *Send anonymous crash reports* toggle
  (default **off**). Sentry / GlitchTip init is now runtime-gated on both a
  baked-in DSN **and** the toggle; turning the toggle off `SentrySDK.close()`s
  the SDK so subsequent crashes are not captured. The Diagnostics row is
  hidden in builds without a `PAYHUB_SENTRY_DSN`.
- **Sub-merchant detail → Cashiers tab** (invite / disable / clear-MFA, same
  flow as 0.3.0 but now scoped inside a `Picker(.segmented)` alongside) and a
  new **API keys tab** (generate / revoke). Plaintext API-key secrets are
  surfaced **once** at create time in a copy-or-it-is-gone sheet — the server
  stores only an argon2 hash.
- **Localised server-error envelope.** A new `ErrorCatalog` resolves ~30
  high-traffic codes (`merchant.last_owner`, `pay_link.quota_exceeded`,
  `sub_merchant.code_taken`, `mfa.invalid_code`, …) to translated strings in
  `Localizable.strings` (EN + AR). Unknown codes fall back to the server's
  English message.

### Changed
- **Upgrades to `payhub-swift` 1.2.0.** `MerchantRawAPI` (the in-app raw
  HTTP shim) and its transparent-refresh closure are deleted — every endpoint
  now goes through the SDK, including `payments` / `settlements` / `devices` /
  `account` / `mfa` / `org` / `subMerchants` (incl. nested `users` and
  `apiKeys`) and `reports.dashboard(groupBySub: true)`. SDK-level transparent
  401 → refresh → retry covers what the closure used to do.
- **Refresh-token-at-rest** is now stored in a Keychain item gated by
  `kSecAccessControl` `[.userPresence, .biometryCurrentSet]` whenever the
  app-lock toggle is on. Toggling app lock on triggers a one-shot rewrap; off
  unwraps transparently. The successful biometric unlock binds its `LAContext`
  to the vault so the SDK's first refresh hits the OS's 5-second cached-auth
  window without re-prompting.
- `AppError` gains a `.validation(code, params, message)` case — server
  validation envelopes now reach the UI with their stable code, ready for
  catalogue lookup. `MerchantValidationError` / `MfaRequiredError` from the
  SDK flow through the typed-error mapping.

### Security
- Refresh tokens at rest are no longer in plain Keychain when app lock is on;
  an OS-enforced biometric / passcode gate is required to unwrap them.

### Tests
- `ErrorCatalogTests` — catalogue hits resolve, unknowns fall back, param
  interpolation works.
- `RefreshTokenVaultTests` — round-trip on/off, rewrap migration, missing-item
  fallthrough.
- `CrashReportingControllerTests` — start / close on the toggle's edges,
  DSN-missing short-circuit.
- `DeepLinkTests` extended for the `https://app.payhub.ly/m/accept-invite`
  form and the legacy `payhub://` form together.

### Known limitations
- Still not compiled in the authoring environment — relies on Xcode / CI.
- Webhook / PSP-gateway / parent-merchant API-key management remains
  web-portal-only.

## [0.3.0] — 2026-05-12

The rest of the merchant surface a shopkeeper or parent owner needs from a phone
— in-app account / 2FA / organisation / sub-merchant management — plus three
pieces of "ship-ready" hardening. Mirrors the Android 0.3.0 slice.

### Added
- **Change password** — More → Security → Change password. Old / new (≥12-char
  client check) / confirm; a TOTP-code field appears when 2FA is on (or on
  `hub.merchant.mfa_required`). `hub.merchant.mfa_required` / `bad_mfa` /
  `bad_credentials` are surfaced inline — **not** as session loss.
- **Two-factor management** — More → Security → Two-factor. Enable → setup key +
  a `CIFilter.qrCodeGenerator` QR → 6-digit confirm; Disable → password.
- **Organisation profile** — More → Business → Organisation profile (parent
  users). Read-only `code` / `status` / `created_at`; the contact / legal /
  address fields editable for a parent **OWNER** (client validation mirrors the
  server; PATCH sends only dirty keys; empty string clears).
- **Sub-merchant & sub-user management** — More → Business → Sub-merchants
  (parent **OWNER** with the aggregator entitlement). Create / edit / list
  sub-merchants (delete refused while payments reference the sub); per sub:
  invite a sub-user (copyable invite link + send channel), edit role / status,
  disable, reissue invite, clear MFA (acting owner's own TOTP).
- **Biometric / device-credential app lock** — More → Security → App lock.
  When on, the app re-prompts via `LAContext` (`.deviceOwnerAuthentication` —
  Face ID / Touch ID with passcode fallback) on cold start and after >2 min
  backgrounded. `NSFaceIDUsageDescription` added. Off by default.
- **Crash / error reporting** → GlitchTip (Sentry protocol) via `getsentry/sentry-cocoa`.
  Off unless a DSN is built in (`PAYHUB_SENTRY_DSN` build setting → Info.plist);
  no PII, crashes/errors only, release-tagged `payhub-merchant-ios@<version>`.

### Changed
- **Raw API calls now ride a transparent 401 → refresh → retry.** `MerchantRawAPI.send`
  takes a `tokenRefresh` closure and retries once on a 401; `MerchantRepository.makeRawAPI`
  wires it to a coalesced `refreshAccessToken()` (an in-flight `Task`, so concurrent
  callers don't burn the single-use refresh token twice). A 401 that survives the
  retry still drops the session.
- **`MerchantRawAPI`** gains the `/merchant/auth/{change-password,mfa/*}`,
  `/merchant/org`, and `/merchant/sub-merchants[/…/users]` endpoints + `Codable`
  models; `mapEnvelope` special-cases the auth-endpoint 401 codes and falls back
  to FastAPI's `{"detail": …}`. `AppError` gains friendly messages for the
  merchant error codes; `MerchantMe+Roles` adds `isParentOwner` / `canManageSubs`.
- **`MoreView`** grows "Security" + (parent-only) "Business" sections; `DeepLink`
  adds the new `MoreRoute` cases + a `SubMerchantsRoute`. `LockManager` is fed
  `@Environment(\.scenePhase)` and overlays `LockView` from `RootView`.
- New SPM dep: `getsentry/sentry-cocoa` (`from: 8.0.0`).

### Tests
- `MerchantRawAPI{Auth,Org,SubMerchants}Tests`, `MerchantMeRolesTests` — the new
  endpoints and the visibility matrix.
- `MerchantRawAPIRefreshTests` — the 401-refresh-retry path; `LockManagerTests` —
  the cold-start / background-timeout / enable-confirm logic.

### Known limitations
- The account / org / sub-merchant endpoints stay raw-HTTP — fold into SDK 1.2.
- `SUB_OWNER` cashier self-management and in-app sub-merchant API-key management
  are still `// TODO(payhub)`.
- Crash reporting has no user-facing opt-out yet (the build-time DSN gates it).
- Still not compiled in the authoring environment — relies on Xcode / the
  standalone repo's CI.

## [0.2.0] — 2026-05-11

Phone-first surface for the most-asked-for mobile queries (payments + settlements),
plus a full Arabic translation. Mirrors the Android 0.2.0 (D6.1) slice.

### Added
- **Payments tab** — new 3rd bottom-nav tab. List with status filter chips
  (All / Pending / Awaiting / Paid / Failed / Cancelled / Refunded), infinite
  scroll, pull-to-refresh, backed by `GET /merchant/payments`. Tapping a row
  pushes a **payment detail** screen with the amount + status pill, copyable
  order ref, PSP + reference, customer mobile (from `metadata.customer_msisdn`),
  the full `payment_events` timeline rendered with a source-coloured leading
  dot per event, the remaining `metadata` as a `LabeledContent` list, and a
  "View pay-link" button that routes through `AppRouter` back to the pay-link
  detail when `metadata.pay_link_id` is present.
- **Settlements** — entry under More → "Settlements". List of settlement files
  (filename, PSP, matched/total + mismatch chip) and a **settlement-detail**
  screen with the per-file counter strip (Total / Matched / Mismatch /
  Missing-in-hub / Missing-in-PSP), filter chips (matched / mismatch /
  missing-in-hub / missing-in-PSP), paginated row list, an inline diff table
  for mismatched rows, and tap-through to a row's payment detail when a
  `payment_id` is present.
- **Full Arabic localisation** — `Sources/Resources/Localizable.strings`
  promoted into `en.lproj/`, with a matching `ar.lproj/Localizable.strings`
  whose labels are pulled from the SPA's `web/src/i18n/locales/ar.ts` where
  the concept maps. Two key styles coexist: structured `payment.detail.title`
  keys for new code, and inline-English-literal keys (`"Pay-links" = "روابط الدفع"`)
  for the unchanged scaffold's `Text("…")` call sites. `PayLinkStatus.label`,
  `PayLinkFilter.label` and `RelativeTime.expiry` switched to
  `NSLocalizedString(_:value:comment:)` so they translate too. `project.yml`
  declares `developmentRegion: en`, `knownRegions: [en, ar, Base]`, and adds
  `CFBundleLocalizations`.

### Changed
- **`MerchantRepository`** gains `payments` / `payment` / `settlements` /
  `settlement` / `settlementRows` — raw HTTP via `MerchantRawAPI` until
  SDK 1.2.
- **`MerchantRawAPI`** gets `listPayments` / `getPayment` / `listSettlements`
  / `getSettlement` / `listSettlementRows` plus mirroring `Codable` models
  (`PaymentRow`, `PaymentEvent`, `PaymentDetail`, `SettlementFile`,
  `SettlementRow`, `JSONValue`) for the Pydantic shapes in
  `app/api/merchant/payments.py` / `app/api/merchant/settlements.py`.
- **`MainTabView`** grows from 3 → 4 tabs (Dashboard / Pay-links / Payments /
  More). `MoreView` adds a "Reports" section with a NavigationLink to
  Settlements, plus a `navigationDestination(for: SettlementsRoute.self)`
  routing both file and (via a settlement row) payment details inside the
  More tab's stack.
- **`PayLinksView.onAppear`** now also replays a parked `router.pendingPayLinkID`
  — fixes the case where a pay-link push tap arrives pre-auth and the value
  is already set when the view first appears (`onChange` only fires on
  subsequent changes).

### Tests
- `MerchantRawAPITests` — `URLProtocol`-stub coverage for all 5 new raw
  endpoints plus device register/unregister and dashboard-by-sub. Asserts
  request shape (path + query + bearer + JSON body) and Codable round-trips.

### Known limitations
- The merchant-payments / settlements endpoints are still raw-HTTP. Fold into
  the SDK with 1.2.
- Currency suffix stays as the ISO code (`LYD`) in both locales to match the
  SPA; the AR `د.ل` symbol is not yet swapped in.

## [0.1.0] — unreleased

Initial scaffold of the native iOS app — the "D7" slice of PayHub's mobile-uplift
plan. Built on the `payhub-swift` SDK's `PayhubMerchantClient` (bearer-token
merchant client).

### Added
- **Auth flow** — server-URL-aware login (on-prem installs), MFA challenge,
  forgot-password sheet, and a `payhub://accept-invite?token=…` deep-link handler.
- **Dashboard** — counter cards (paid + volume, in-flight, active pay-links,
  needs-follow-up), a 24h / 3d / 7d window picker, "other outcomes" breakdown,
  and a best-effort per-shop section for parent merchants (raw `?group_by=sub`
  call — falls back to a notice if the server doesn't include `sub_breakdown`).
- **Pay-links** — filterable list (All / Needs follow-up / Active / Paid /
  Expired / Cancelled), pull-to-refresh, cursor paging, create sheet (amount,
  description, customer phone, PSP allow-list, expiry, auto-generated order ref,
  `ShareLink` confirmation), and a detail screen with re-share / extend / clone /
  cancel actions gated on a write role.
- **More** — profile + entitlements summary, a push-notifications toggle wired to
  `UNUserNotificationCenter` + APNs registration + a raw `POST /merchant/devices`,
  request-password-reset, sign out, and an app/server footer.
- **Infrastructure** — `MerchantRepository` (wraps the SDK, maps `PayhubError` →
  `AppError`, publishes auth state), `KeychainTokenStore` (token pair in the
  Keychain, transparent-refresh-aware), `MerchantRawAPI` (the few endpoints not
  yet in the SDK), `PushManager` + `AppDelegate` (APNs + notification taps),
  brand theming (amber `AccentColor`, app icon generated from the PayHub mark),
  reusable components, and unit tests for formatting / deep-link parsing / error
  mapping.
- **Tooling** — XcodeGen `project.yml`, GitHub Actions CI (build + test +
  SwiftLint; a disabled TestFlight release job stub), `.swiftlint.yml`.

### Known gaps (pending `payhub-swift` 1.2)
- No in-app merchant-payments list, change-password, MFA management, settlements,
  or sub-merchant management — those endpoints aren't in the 1.1.0 SDK. Marked
  with `// TODO(payhub):` where relevant.
- The dashboard's per-shop breakdown depends on the server returning
  `sub_breakdown` from `GET /merchant/dashboard?group_by=sub`; the app degrades
  gracefully if it doesn't.

### Notes
- The Xcode project is generated by XcodeGen (`xcodegen generate`) and is **not**
  committed — see the README.
- `project.yml` depends on `payhub-swift` via a local `path:` (`../../sdks/swift`)
  until 1.1.0 is published to the `safwatech/payhub-swift` mirror; switch to a
  versioned `url:` dep then.
- Could not be compiled in the authoring environment (no Xcode / Swift
  toolchain) — relies on Xcode / the standalone repo's CI to build.
