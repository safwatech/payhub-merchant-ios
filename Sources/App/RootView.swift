import SwiftUI

/// Top-level switch: launch splash → login flow → main tab view.
/// An accept-invite deep link is presented as a sheet over whatever's showing.
struct RootView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            switch repository.authState {
            case .undetermined:
                LaunchView()
            case .unauthenticated:
                LoginView()
            case .authenticated:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: repository.authState)
        .sheet(item: invitePresentation) { presentation in
            AcceptInviteView(link: presentation.link)
        }
    }

    /// Bridges `router.pendingInvite` into a sheet `item:` binding.
    private var invitePresentation: Binding<InvitePresentation?> {
        Binding(
            get: {
                if case let .acceptInvite(token, m, u, s)? = router.pendingInvite {
                    return InvitePresentation(link: .acceptInvite(token: token, merchantCode: m, username: u, subCode: s))
                }
                return nil
            },
            set: { newValue in if newValue == nil { router.pendingInvite = nil } }
        )
    }
}

private struct InvitePresentation: Identifiable {
    let link: DeepLink
    var id: String {
        if case let .acceptInvite(token, _, _, _) = link { return token }
        return UUID().uuidString
    }
}

/// Branded launch view shown while we validate the persisted session.
struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                AppMarkView(size: 96)
                Text(AppInfo.name)
                    .font(.title2.weight(.semibold))
                ProgressView()
                    .padding(.top, 8)
            }
        }
    }
}
