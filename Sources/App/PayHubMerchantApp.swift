import SwiftUI

/// "PayHub Merchant" — the native iOS companion app for PayHub merchants.
/// Sign in, watch the dashboard, create and follow up on pay-links, manage push.
@main
struct PayHubMerchantApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var settings = AppSettings.shared
    @StateObject private var repository = MerchantRepository()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(repository)
                .environmentObject(router)
                .tint(Brand.amber)
                .task {
                    // Wire the delegate ↔ router/push, then validate the persisted session.
                    appDelegate.router = router
                    PushManager.shared.repository = repository
                    await PushManager.shared.refreshAuthorizationStatus()
                    await repository.bootstrap()
                }
                .onOpenURL { url in router.handleURL(url) }
        }
    }
}
