import SwiftUI

/// "Send anonymous crash reports" opt-in. Off by default; hidden entirely in
/// builds without a baked-in `PAYHUB_SENTRY_DSN`. The toggle's value writes
/// through `AppSettings.crashReportingEnabled`, and `PayHubMerchantApp`'s
/// `onChange` re-applies `CrashReportingController` so flipping it starts /
/// stops Sentry without a restart.
struct DiagnosticsView: View {
    @EnvironmentObject private var settings: AppSettings

    /// `false` ⇒ this build has no DSN baked in, the controller is a no-op
    /// forever, and the toggle is replaced by the unavailable copy.
    private var isAvailable: Bool { !AppInfo.sentryDSN.isEmpty }

    var body: some View {
        Form {
            if isAvailable {
                Section {
                    Toggle(LocalizedStringKey("diagnostics.toggle"),
                           isOn: Binding(get: { settings.crashReportingEnabled },
                                          set: { settings.crashReportingEnabled = $0 }))
                } footer: {
                    Text(LocalizedStringKey("diagnostics.blurb"))
                }
            } else {
                Section {
                    Text(LocalizedStringKey("diagnostics.unavailable"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(LocalizedStringKey("diagnostics.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
