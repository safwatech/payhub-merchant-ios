import Foundation

/// App bundle metadata, read once.
enum AppInfo {
    static let name = "PayHub Merchant"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var versionDisplay: String {
        "\(version) (\(build))"
    }
}
