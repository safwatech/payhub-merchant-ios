import Foundation
import Combine
import UserNotifications
import Payhub

@MainActor
final class MoreViewModel: ObservableObject {
    @Published var pushEnabled: Bool
    @Published private(set) var pushAuthorizationDenied = false
    @Published private(set) var isSigningOut = false
    @Published var error: AppError?

    private weak var repository: MerchantRepository?
    private let settings: AppSettings
    private let push: PushManager

    init(settings: AppSettings = .shared, push: PushManager = .shared) {
        self.settings = settings
        self.push = push
        self.pushEnabled = settings.pushEnabled
    }

    func bind(repository: MerchantRepository) { self.repository = repository }

    var me: MerchantMe? { repository?.me }

    func refresh() async {
        await push.refreshAuthorizationStatus()
        // If the OS revoked the permission, reflect that.
        let status = push.authorizationStatus
        pushAuthorizationDenied = (status == .denied)
        if status == .denied { pushEnabled = false; settings.pushEnabled = false }
    }

    func setPush(_ on: Bool) {
        Task {
            if on {
                let granted = await push.enable()
                if granted {
                    settings.pushEnabled = true
                    pushEnabled = true
                } else {
                    settings.pushEnabled = false
                    pushEnabled = false
                    pushAuthorizationDenied = true
                }
            } else {
                settings.pushEnabled = false
                pushEnabled = false
                await push.disable()
            }
        }
    }

    func signOut() {
        guard let repository else { return }
        isSigningOut = true
        Task {
            await repository.signOut()
            isSigningOut = false
            // authState flips → RootView shows LoginView.
        }
    }

    func reloadMe() {
        guard let repository else { return }
        Task {
            do { _ = try await repository.refreshMe() }
            catch { self.error = AppError.from(error) }
        }
    }
}
