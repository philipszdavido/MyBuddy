//
//  MyBuddyApp.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 5/3/24.
//

import SwiftUI
import Firebase

extension EnvironmentValues {
    @Entry var debugMode: Bool = true
}

@main
struct MyBuddyApp: App {
    let persistenceController = PersistenceController.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject var auth = AuthViewModel()
    @StateObject private var contactListVM: ContactListViewModel

    init() {
        let context = persistenceController.container.viewContext
        _contactListVM = StateObject(wrappedValue: ContactListViewModel(context: context))
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
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}
