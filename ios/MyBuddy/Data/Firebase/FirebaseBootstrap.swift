//
//  FirebaseBootstrap.swift
//
//  Chooses the Firebase project for the current environment and (development only) points the SDKs at
//  the local Firebase Emulator Suite. Called from the composition root / app delegate only.
//

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

enum FirebaseBootstrap {

    static func configureIfNeeded(_ configuration: AppConfiguration, bundle: Bundle = .main) {
        guard FirebaseApp.app() == nil else { return }

        var specificFile: String?
        switch configuration.environment {
        case .development: specificFile = "GoogleService-Info-Dev"
        case .staging: specificFile = "GoogleService-Info-Staging"
        case .production, .test: specificFile = nil
        }

        if let name = specificFile,
           let path = bundle.path(forResource: name, ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
        } else {
            if configuration.environment == .staging {
                // A staging build silently talking to production data is worse than not launching.
                fatalError("Missing GoogleService-Info-Staging.plist; refusing to run a staging build against the default project.")
            }
            if configuration.environment == .development {
                Log.app.warning("GoogleService-Info-Dev.plist not found; development is using the default Firebase project")
            }
            FirebaseApp.configure()
        }

        configureEmulatorIfRequested(configuration)
    }

    /// Must run before any Auth/Firestore/Storage call.
    private static func configureEmulatorIfRequested(_ configuration: AppConfiguration) {
        guard configuration.environment == .development, let host = configuration.emulatorHost else { return }
        Auth.auth().useEmulator(withHost: host, port: 9099)
        Firestore.firestore().useEmulator(withHost: host, port: 8080)
        Storage.storage().useEmulator(withHost: host, port: 9199)
        Log.app.notice("Using Firebase emulators at \(host, privacy: .public)")
    }
}
