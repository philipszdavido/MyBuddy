//
//  FirebasePushNotificationService.swift
//
//  Tokens live at users/{uid}/devices/{installationId}: one document per install, so a user can
//  have many devices and each is removed independently on logout.
//

import Foundation
import UIKit
import UserNotifications
import FirebaseFirestore
import FirebaseMessaging

final class FirebasePushNotificationService: PushNotificationService, @unchecked Sendable {
    private let db: Firestore
    private static let installationKey = "mb.installationID"

    init(db: Firestore = Firestore.firestore()) { self.db = db }

    private var installationID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.installationKey) { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: Self.installationKey)
        return created
    }

    func requestAuthorization() async throws -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
            return granted
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    func registerDevice(userID: String) async throws {
        do {
            let token = try await Messaging.messaging().token()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            try await db.collection("users").document(userID)
                .collection("devices").document(installationID)
                .setData([
                    "token": token,
                    "platform": "ios",
                    "appVersion": version,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    func unregisterDevice(userID: String) async throws {
        do {
            try await db.collection("users").document(userID)
                .collection("devices").document(installationID).delete()
            // Invalidate the token so a signed-out device stops receiving pushes.
            try? await Messaging.messaging().deleteToken()
        } catch { throw FirebaseErrorMapper.map(error) }
    }
}
