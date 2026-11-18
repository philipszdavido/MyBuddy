//
//  AppContainer.swift
//  MyBuddy
//
//  Composition root. The ONLY place that chooses a backend. Everything else
//  receives protocols. Repositories are Sendable, so they may be read from any
//  context; the view model is main-actor only.
//

import Foundation
import FirebaseMessaging

final class AppContainer: @unchecked Sendable {
    static let shared = AppContainer(configuration: .current())

    let configuration: AppConfiguration
    let authService: AuthenticationService
    let userRepository: UserRepository
    let chatRepository: ChatRepository
    let feedRepository: FeedRepository
    let pushService: PushNotificationService
    let mediaRepository: MediaRepository
    let safetyRepository: SafetyRepository
    /// Social features (posts with media, comments, profiles, search, activity). `nil` on backends
    /// that don't offer them (Firebase); the UI hides those features then.
    let socialRepository: SocialRepository?
    /// API-native conversations (groups, message requests). `nil` on Firebase (Core Data chat is used).
    let messagingRepository: MessagingRepository?
    /// Profile editing, privacy and notification settings. `nil` on Firebase.
    let accountRepository: AccountRepository?

    @MainActor private var cachedAuthViewModel: AuthViewModel?
    @MainActor private var cachedRouter: DeepLinkRouter?

    @MainActor var deepLinkRouter: DeepLinkRouter {
        if let existing = cachedRouter { return existing }
        let created = DeepLinkRouter()
        cachedRouter = created
        return created
    }

    @MainActor var authViewModel: AuthViewModel {
        if let existing = cachedAuthViewModel { return existing }
        let created = AuthViewModel(authService: authService, userRepository: userRepository, pushService: pushService)
        cachedAuthViewModel = created
        return created
    }

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        switch configuration.backend {
        case .firebase:
            FirebaseBootstrap.configureIfNeeded(configuration)
            authService = FirebaseAuthenticationService()
            userRepository = FirebaseUserRepository()
            chatRepository = FirebaseChatRepository()
            feedRepository = FirebaseFeedRepository()
            pushService = FirebasePushNotificationService()
            mediaRepository = FirebaseMediaRepository()
            safetyRepository = FirebaseSafetyRepository()
            socialRepository = nil
            messagingRepository = nil
            accountRepository = nil
        case .api:
            // Firebase remains the identity provider (ID tokens) and the push transport (FCM).
            FirebaseBootstrap.configureIfNeeded(configuration)
            let auth = FirebaseAuthenticationService()
            let baseURL = configuration.apiBaseURL!
            let tokens: @Sendable (Bool) async throws -> String = { force in try await auth.idToken(forceRefresh: force) }
            let api = APIClient(baseURL: baseURL, tokenProvider: tokens)
            let realtime = RealtimeClient(baseURL: baseURL, tokenProvider: tokens)
            let social = APISocialRepository(api: api)
            authService = auth
            userRepository = APIUserRepository(api: api, authUID: { auth.currentUser?.id })
            chatRepository = APIChatRepository(api: api, realtime: realtime)
            feedRepository = APIFeedRepository(api: api)
            pushService = APIPushNotificationService(
                api: api,
                fcmToken: { try await Messaging.messaging().token() },
                deleteFCMToken: { try? await Messaging.messaging().deleteToken() }
            )
            mediaRepository = APIMediaRepository(social: social)
            safetyRepository = APISafetyRepository(api: api)
            socialRepository = social
            messagingRepository = APIMessagingRepository(api: api, realtime: realtime)
            accountRepository = APIAccountRepository(api: api, social: social)
        case .mock:
            // UI tests may start signed in (MBUITestingSignedIn=1) to reach screens without typing credentials.
            if ProcessInfo.processInfo.environment["MBUITestingSignedIn"] == "1" {
                authService = MockAuthenticationService(signedIn: AuthUser(id: "me", email: "me@example.com", isEmailVerified: true))
                userRepository = MockUserRepository([UserAccount(id: "me", email: "me@example.com", displayName: "Me",
                                                                 phoneNumber: 2348000000000, photoURL: nil, createdAt: Date())])
            } else {
                authService = MockAuthenticationService()
                userRepository = MockUserRepository()
            }
            chatRepository = MockChatRepository()
            feedRepository = MockFeedRepository()
            pushService = MockPushNotificationService()
            mediaRepository = MockMediaRepository()
            safetyRepository = MockSafetyRepository()
            socialRepository = MockSocialRepository()
            messagingRepository = MockMessagingRepository()
            accountRepository = MockAccountRepository()
        }
    }
}
