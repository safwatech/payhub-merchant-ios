# Changelog

All notable changes to **PayHub Merchant** (iOS) are documented here. This
project follows [Semantic Versioning](https://semver.org/).

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
