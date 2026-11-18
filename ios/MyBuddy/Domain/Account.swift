//
//  Account.swift
//  MyBuddy
//
//  The signed-in user's editable profile, privacy settings and notification preferences
//  (MyBuddy API backend).
//

import Foundation

enum MessagePermission: String, Sendable, CaseIterable, Identifiable {
    case everyone = "EVERYONE", connections = "CONNECTIONS", nobody = "NOBODY"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone: return String(localized: "Everyone")
        case .connections: return String(localized: "Contacts & people I follow")
        case .nobody: return String(localized: "No one")
        }
    }
}

struct PrivacySettings: Sendable, Equatable {
    var showActivityStatus: Bool
    var sendReadReceipts: Bool
    var allowMessagesFrom: MessagePermission
    var discoverable: Bool
}

struct AccountProfile: Sendable, Equatable {
    let id: String
    var username: String?
    var displayName: String
    var bio: String?
    var location: String?
    var website: String?
    var avatarURL: URL?
    var visibility: AccountVisibility
    var email: String?
    var phoneNumber: String?
    var phoneVerified: Bool
    var settings: PrivacySettings
    var followersCount: Int
    var followingCount: Int
    var postsCount: Int
}

struct ProfileChanges: Sendable, Equatable {
    var username: String?
    var displayName: String?
    var bio: String?
    var location: String?
    var website: String?
    var visibility: AccountVisibility?
}

struct NotificationPreference: Sendable, Equatable, Identifiable {
    let type: ActivityType
    var push: Bool
    var inApp: Bool
    var id: String { type.rawValue }
}

enum UsernameStatus: Sendable, Equatable { case available, taken, invalid }

protocol AccountRepository: Sendable {
    func me() async throws -> AccountProfile
    func update(_ changes: ProfileChanges) async throws -> AccountProfile
    func usernameStatus(_ username: String) async throws -> UsernameStatus
    func updatePrivacy(_ settings: PrivacySettings) async throws -> AccountProfile
    /// Uploads, waits for processing, and sets it as the avatar. `onProgress` reports 0...1.
    func setAvatar(_ jpeg: Data, onProgress: @escaping @Sendable (Double) -> Void) async throws -> AccountProfile
    func removeAvatar() async throws -> AccountProfile
    func notificationPreferences() async throws -> [NotificationPreference]
    func setNotificationPreference(_ preference: NotificationPreference) async throws
}

extension ActivityType {
    var settingsTitle: String {
        switch self {
        case .follow: return String(localized: "New followers")
        case .followRequest: return String(localized: "Follow requests")
        case .followAccepted: return String(localized: "Accepted requests")
        case .postReaction: return String(localized: "Likes on your posts")
        case .comment: return String(localized: "Comments")
        case .commentReply: return String(localized: "Replies")
        case .commentReaction: return String(localized: "Likes on your comments")
        case .mention: return String(localized: "Mentions")
        case .repost: return String(localized: "Reposts")
        case .message: return String(localized: "Messages")
        case .messageRequest: return String(localized: "Message requests")
        }
    }
}
