//
//  APIPushNotificationService.swift
//  MyBuddy
//
//  Registers this installation's FCM token with the MyBuddy API. FCM stays the push transport;
//  token access is injected by the composition root so this file needs no Firebase import.
//

import Foundation
import UIKit
import UserNotifications

final class APIPushNotificationService: PushNotificationService, @unchecked Sendable {
    private let api: APIClient
    private let fcmToken: @Sendable () async throws -> String
    private let deleteFCMToken: @Sendable () async -> Void
    private static let installationKey = "mb.installationID"

    /// FCM token access is injected by the composition root (FCM itself stays the push transport).
    init(api: APIClient, fcmToken: @escaping @Sendable () async throws -> String, deleteFCMToken: @escaping @Sendable () async -> Void) {
        self.api = api
        self.fcmToken = fcmToken
        self.deleteFCMToken = deleteFCMToken
    }

    private var installationID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.installationKey) { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: Self.installationKey)
        return created
    }

    func requestAuthorization() async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        if granted { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
        return granted
    }

    func registerDevice(userID: String) async throws {
        struct Body: Encodable { let fcmToken: String; let platform: String; let appVersion: String?; let locale: String? }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let body = Body(fcmToken: try await fcmToken(), platform: "ios", appVersion: version, locale: Locale.current.identifier)
        try await api.put("devices/\(installationID)", body: body)
    }

    func unregisterDevice(userID: String) async throws {
        try await api.delete("devices/\(installationID)")
        await deleteFCMToken()
    }
}

