//
//  MyBuddyApp.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 5/3/24.
//

import SwiftUI
import Firebase
import FirebaseMessaging
import UserNotifications

extension EnvironmentValues {
    @Entry var debugMode: Bool = true
}

@main
struct MyBuddyApp: App {
    let persistenceController = PersistenceController.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject var auth = AuthViewModel.shared
    @StateObject private var router = AppContainer.shared.deepLinkRouter
    @StateObject private var contactListVM: ContactListViewModel

    init() {
        let context = persistenceController.container.viewContext
        _contactListVM = StateObject(wrappedValue: ContactListViewModel(context: context, userRepository: AppContainer.shared.userRepository))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if auth.user != nil {
                    ContentView()
                        .environmentObject(contactListVM) // 🔁 Pass to ContentView
                } else {
                    NavigationStack {
                        WelcomeView()
                    }
                }
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .environmentObject(auth)
            .environmentObject(router)
            .onOpenURL { router.handle(url: $0) }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configureIfNeeded(AppContainer.shared.configuration)
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.app.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    // FCM token created or rotated.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in await AppContainer.shared.authViewModel.registerPushIfSignedIn() }
    }

    // Foreground: show a banner unless the user is already looking at that conversation.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let link = DeepLink(userInfo: notification.request.content.userInfo)
        let suppress = await MainActor.run { () -> Bool in
            if case .chat(let id)? = link { return AppContainer.shared.deepLinkRouter.activeChatID == id }
            return false
        }
        return suppress ? [] : [.banner, .list, .sound]
    }

    // Tap on a notification (cold, warm or background launch).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let link = DeepLink(userInfo: response.notification.request.content.userInfo)
        await MainActor.run { AppContainer.shared.deepLinkRouter.handle(link) }
    }
}
