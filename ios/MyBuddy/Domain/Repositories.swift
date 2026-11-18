//
//  Repositories.swift
//  MyBuddy
//
//  Protocols the app depends on. Firebase (or a future REST/WebSocket backend)
//  implements them in Data/. No Firebase imports allowed here.
//

import Foundation

protocol AuthenticationService: Sendable {
    var currentUser: AuthUser? { get }
    /// Emits the current user immediately, then on every change. Finishes when the consumer cancels.
    func authStateChanges() -> AsyncStream<AuthUser?>
    func signIn(email: String, password: String) async throws -> AuthUser
    /// Required by providers before sensitive operations such as account deletion.
    func reauthenticate(password: String) async throws
    func register(email: String, password: String) async throws -> AuthUser
    func sendPasswordReset(email: String) async throws
    func sendEmailVerification() async throws
    func signOut() throws
    func deleteAccount() async throws
    /// Short-lived bearer token for the MyBuddy API (Firebase ID token). `forceRefresh` after a 401.
    func idToken(forceRefresh: Bool) async throws -> String
}

protocol UserRepository: Sendable {
    func account(id: String) async throws -> UserAccount?
    func save(_ account: UserAccount) async throws
    /// `nil` removes the profile photo.
    func updatePhoto(id: String, media: UploadedMedia?) async throws
    /// Looks up accounts for these numbers (e.g. to refresh known contacts). Never removes contacts.
    /// Deduplicates and chunks internally.
    func accounts(matchingPhoneNumbers numbers: [Int64]) async throws -> [UserAccount]
    /// Matches the *whole* device address book; contacts no longer in it stop being contacts.
    func syncContacts(phoneNumbers numbers: [Int64]) async throws -> [UserAccount]
}

protocol ChatRepository: Sendable {
    /// Bounded live stream of the most recent conversations.
    func observeConversations(userID: String, limit: Int) -> AsyncThrowingStream<[Conversation], Error>
    /// Bounded live stream of the newest `limit` messages (newest first). Cancel the consuming task to detach the listener.
    func observeLatestMessages(conversationID: String, limit: Int) -> AsyncThrowingStream<[ChatMessage], Error>
    func loadOlderMessages(conversationID: String, before cursor: MessageCursor, limit: Int) async throws -> MessagePage
    /// Idempotent: calling twice with the same `OutgoingMessage.id` yields one message.
    func send(_ message: OutgoingMessage) async throws
    /// The id of the one-to-one conversation between the two users, creating it if needed.
    func conversationID(currentUserID: String, currentPhone: Int64, recipientID: String, recipientPhone: Int64) async throws -> String
}

protocol FeedRepository: Sendable {
    /// Bounded live stream of the signed-in user's own feed (newest first).
    func observeFeed(ownerPhone: Int64, limit: Int) -> AsyncThrowingStream<[FeedPost], Error>
    /// Idempotent on `post.id`. Always includes the author's own feed.
    func publish(_ post: NewPost, recipientPhones: [Int64]) async throws
    /// `nil` removes the user's reaction. One reaction per (post, user).
    func setReaction(postID: String, userID: String, reaction: Reaction?) async throws
    func reactionSummary(postID: String, userID: String) async throws -> ReactionSummary
}

protocol PushNotificationService: Sendable {
    /// Asks the user for permission (system prompt shows once) and registers for remote notifications.
    func requestAuthorization() async throws -> Bool
    /// Stores this device's push token for the user. A user may have many devices.
    func registerDevice(userID: String) async throws
    /// Removes this device's token (logout / account deletion).
    func unregisterDevice(userID: String) async throws
}

protocol MediaRepository: Sendable {
    /// Uploads JPEG data and returns the stored media (id + display URL). `path` identifies the purpose
    /// (chat image or avatar); on Firebase the same path overwrites, so retries are idempotent.
    func uploadImage(_ data: Data, path: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> UploadedMedia
    /// Best-effort delete; URLs that do not belong to this backend are ignored.
    func delete(url: String) async throws
}

enum MediaPath {
    static func chatImage(userID: String, messageID: String) -> String { "chat_images/\(userID)/\(messageID).jpg" }
    static func avatar(userID: String, imageID: String) -> String { "avatars/\(userID)/\(imageID).jpg" }
}

protocol SafetyRepository: Sendable {
    func block(_ user: BlockedUser, by userID: String) async throws
    func unblock(userID: String, by blockerID: String) async throws
    /// Bounded live stream of the users `userID` has blocked.
    func observeBlockedUsers(for userID: String, limit: Int) -> AsyncThrowingStream<[BlockedUser], Error>
    /// Files a report for moderators. Reports are write-only for clients.
    func report(targetUserID: String, reporterID: String, reason: ReportReason,
                conversationID: String?, messageID: String?) async throws
}
