import SwiftUI

/// "PayHub Merchant" — the native iOS companion app for PayHub merchants.
/// Sign in, watch the dashboard, create and follow up on pay-links, manage push.
@main
struct PayHubMerchantApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var settings = AppSettings.shared
    @StateObject private var repository = MerchantRepository()
    @StateObject private var router = AppRouter()
    @StateObject private var lock = LockManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(repository)
                .environmentObject(router)
                .environmentObject(lock)
                .tint(Brand.amber)
                .task {
                    // Wire the delegate ↔ router/push, then validate the persisted session.
                    appDelegate.router = router
                    PushManager.shared.repository = repository
                    await PushManager.shared.refreshAuthorizationStatus()
                    await repository.bootstrap()
                }
                .onOpenURL { url in router.handleURL(url) }
                .onChange(of: scenePhase) { phase in lock.handleScenePhase(phase) }
        }
    }
}
