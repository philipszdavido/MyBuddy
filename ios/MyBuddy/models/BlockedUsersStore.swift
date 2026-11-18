//
//  BlockedUsersStore.swift
//  MyBuddy
//
//  Live list of users the signed-in user has blocked, plus report/block/unblock actions.
//  Blocking is enforced by the backend (rules reject messages from a blocked sender); this store also
//  hides the blocked user's chats and feed posts locally.
//

import Foundation

@MainActor
final class BlockedUsersStore: ObservableObject {
    static let shared = BlockedUsersStore(repository: AppContainer.shared.safetyRepository)
    static let limit = 500

    @Published private(set) var blocked: [BlockedUser] = []
    private let repository: SafetyRepository
    private var currentUserID: String?

    init(repository: SafetyRepository) { self.repository = repository }

    var ids: Set<String> { Set(blocked.map(\.id)) }
    var phones: Set<Int64> { Set(blocked.map(\.phoneNumber)) }

    func isBlocked(userID: String) -> Bool { blocked.contains { $0.id == userID } }

    /// Run from `.task(id: userID)`; the listener is removed when the task is cancelled.
    func sync(userID: String) async {
        currentUserID = userID
        do {
            for try await users in repository.observeBlockedUsers(for: userID, limit: Self.limit) {
                blocked = users
            }
        } catch {
            Log.app.error("blocked users sync ended: \(AppError.wrap(error).diagnostic, privacy: .public)")
        }
    }

    func clear() {
        blocked = []
        currentUserID = nil
    }

    func block(_ user: BlockedUser) async throws {
        guard let me = currentUserID else { throw AppError.authentication(.notSignedIn) }
        guard user.id != me else { throw AppError.validation("You can't block yourself.") }
        // Optimistic: hide immediately; the stream confirms (or the error below reverts it).
        if !isBlocked(userID: user.id) { blocked.insert(user, at: 0) }
        do { try await repository.block(user, by: me) }
        catch {
            blocked.removeAll { $0.id == user.id }
            throw AppError.wrap(error)
        }
    }

    func unblock(userID: String) async throws {
        guard let me = currentUserID else { throw AppError.authentication(.notSignedIn) }
        let previous = blocked
        blocked.removeAll { $0.id == userID }
        do { try await repository.unblock(userID: userID, by: me) }
        catch {
            blocked = previous
            throw AppError.wrap(error)
        }
    }

    func report(userID: String, reason: ReportReason, conversationID: String?) async throws {
        guard let me = currentUserID else { throw AppError.authentication(.notSignedIn) }
        do {
            try await repository.report(targetUserID: userID, reporterID: me, reason: reason,
                                        conversationID: conversationID, messageID: nil)
        } catch { throw AppError.wrap(error) }
    }
}
