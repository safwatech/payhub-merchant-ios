import SwiftUI

/// The signed-in shell: a bottom `TabView`. Each tab view owns its own
/// `NavigationStack` so deep-link-driven programmatic navigation is local to it.
struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem { Label(LocalizedStringKey("tab.dashboard"), systemImage: "chart.bar.xaxis") }
                .tag(MainTab.dashboard)

            PayLinksView()
                .tabItem { Label(LocalizedStringKey("tab.payLinks"), systemImage: "link") }
                .tag(MainTab.payLinks)

            PaymentsView()
                .tabItem { Label(LocalizedStringKey("tab.payments"), systemImage: "creditcard") }
                .tag(MainTab.payments)

            MoreView()
                .tabItem { Label(LocalizedStringKey("tab.more"), systemImage: "ellipsis.circle") }
                .tag(MainTab.more)
        }
    }
}
