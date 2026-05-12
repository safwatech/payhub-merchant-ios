import Foundation
import Payhub

/// Non-secret, persisted preferences (UserDefaults). Secrets live in the Keychain.
///
/// `serverURL` matters because PayHub is on-prem / single-tenant — a self-hosted
/// install runs at its own host, so the user must be able to point the app at it.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let serverURL = "payhub.serverURL"
        static let pushEnabled = "payhub.pushEnabled"
        static let appLockEnabled = "payhub.appLockEnabled"
        static let lastMerchantCode = "payhub.lastMerchantCode"
        static let lastUsername = "payhub.lastUsername"
        static let lastSubCode = "payhub.lastSubCode"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.serverURLString = defaults.string(forKey: Key.serverURL)
            ?? PayhubClient.defaultBaseURL.absoluteString
        self.pushEnabled = defaults.bool(forKey: Key.pushEnabled)
        self.appLockEnabled = defaults.bool(forKey: Key.appLockEnabled)
    }

    @Published var serverURLString: String {
        didSet { defaults.set(serverURLString, forKey: Key.serverURL) }
    }

    @Published var pushEnabled: Bool {
        didSet { defaults.set(pushEnabled, forKey: Key.pushEnabled) }
    }

    /// Opt-in: gate the authenticated UI behind Face ID / Touch ID / device passcode.
    @Published var appLockEnabled: Bool {
        didSet { defaults.set(appLockEnabled, forKey: Key.appLockEnabled) }
    }

    /// Parsed server URL, falling back to the default if the stored string is junk.
    var serverURL: URL {
        URL(string: serverURLString.trimmingCharacters(in: .whitespaces)) ?? PayhubClient.defaultBaseURL
    }

    func resetServerURL() {
        serverURLString = PayhubClient.defaultBaseURL.absoluteString
    }

    // Login pre-fill — convenience only, never the password.
    var lastMerchantCode: String? {
        get { defaults.string(forKey: Key.lastMerchantCode) }
        set { defaults.set(newValue, forKey: Key.lastMerchantCode) }
    }
    var lastUsername: String? {
        get { defaults.string(forKey: Key.lastUsername) }
        set { defaults.set(newValue, forKey: Key.lastUsername) }
    }
    var lastSubCode: String? {
        get { defaults.string(forKey: Key.lastSubCode) }
        set { defaults.set(newValue, forKey: Key.lastSubCode) }
    }
}
