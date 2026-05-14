import Foundation
import Sentry

/// Runtime-gated crash reporting (Sentry / GlitchTip protocol).
///
/// Off by default. `apply(enabled:)` is the single entry point: it fires
/// `SentrySDK.start` when both gates are open — the toggle is on **and** a
/// non-blank build-time DSN is baked in — and `SentrySDK.close()`s the SDK
/// when either gate flips off. No PII: `tracesSampleRate = 0`,
/// `sendDefaultPii = false`, session tracking disabled, release tag is
/// `payhub-merchant-ios@<MARKETING_VERSION>`.
///
/// The controller is intentionally dependency-light — its single
/// `dsn: String` argument is normally `AppInfo.sentryDSN`, but tests inject a
/// mock by constructing it with a string and inspecting `apply` side-effects
/// via the `applyCount` counter (which doesn't touch `SentrySDK` when the DSN
/// is blank — so unit tests run without a real Sentry).
///
/// Mirrors `apps/merchant-android/.../util/CrashReportingController.kt` 1:1.
///
/// See `docs/superpowers/specs/2026-05-14-d6-d7-sdk-1.2-and-app-followups-design.md`
/// §3.4 for the no-PII contract.
@MainActor
final class CrashReportingController {
    private let dsn: String
    private let releaseVersion: String
    private let environment: String

    /// How many times `apply` was invoked — `==0` means "no-op forever"
    /// because the build has no DSN. Tests assert against this to verify
    /// the controller flips Sentry on/off in response to the toggle.
    private(set) var applyCount: Int = 0
    private(set) var lastAppliedValue: Bool? = nil

    init(dsn: String = AppInfo.sentryDSN,
         releaseVersion: String = AppInfo.version,
         environment: String? = nil) {
        self.dsn = dsn
        self.releaseVersion = releaseVersion
        if let environment {
            self.environment = environment
        } else {
            #if DEBUG
            self.environment = "debug"
            #else
            self.environment = "release"
            #endif
        }
    }

    /// `true` when the build is capable of crash reporting (a DSN was baked
    /// in). The Diagnostics screen hides the toggle when this is false.
    var isAvailable: Bool { !dsn.isEmpty }

    /// Start / stop Sentry in response to the toggle. Idempotent: re-applying
    /// the same value is a cheap no-op for the toggle but still increments
    /// the counter so tests can verify the call path was reached.
    func apply(enabled: Bool) {
        applyCount += 1
        lastAppliedValue = enabled
        guard !dsn.isEmpty else { return }   // build never carried a DSN — no-op forever.
        if enabled {
            SentrySDK.start { options in
                options.dsn = self.dsn
                options.releaseName = "payhub-merchant-ios@\(self.releaseVersion)"
                options.environment = self.environment
                options.tracesSampleRate = 0.0
                options.enableAutoSessionTracking = false
                options.sendDefaultPii = false
                options.attachStacktrace = true
            }
        } else {
            SentrySDK.close()
        }
    }
}
