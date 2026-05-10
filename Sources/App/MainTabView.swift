import SwiftUI

/// The signed-in shell: a bottom `TabView`. Each tab view owns its own
/// `NavigationStack` so deep-link-driven programmatic navigation is local to it.
struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.xaxis") }
                .tag(MainTab.dashboard)

            PayLinksView()
                .tabItem { Label("Pay-links", systemImage: "link") }
                .tag(MainTab.payLinks)

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(MainTab.more)
        }
    }
}
