//
//  AuthViewModel.swift
//  MyBuddy
//
//  Depends only on domain protocols (AuthenticationService / UserRepository).
//  Public completion-handler API is kept so existing views keep compiling;
//  each wraps an async implementation.
//

import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    static var shared: AuthViewModel { AppContainer.shared.authViewModel }

    @Published private(set) var user: AuthUser?
    @Published private(set) var userProfile: UserAccount?
    @Published private(set) var isLoading = true

    /// The backend's id for the signed-in account (Firebase: the uid; MyBuddy API: a server UUID).
    /// Local data (messages, outbox, contacts) is keyed by this, not by the auth provider's uid.
    var accountID: String? { userProfile?.id }

    private let authService: AuthenticationService
    private let userRepository: UserRepository
    private let pushService: PushNotificationService
    private let coreDataUtils = CoreDataUtils.shared
    private let contactManager = ContactManager()
    private var stateTask: Task<Void, Never>?

    private static let lastUIDKey = "mb.lastSignedInUID"

    init(authService: AuthenticationService, userRepository: UserRepository, pushService: PushNotificationService) {
        self.authService = authService
        self.userRepository = userRepository
        self.pushService = pushService

        let stream = authService.authStateChanges()
        stateTask = Task { [weak self] in
            for await authUser in stream {
                guard let self else { return }
                self.user = authUser
                self.isLoading = false
                if let authUser {
                    await self.refreshProfile(uid: authUser.id)
                    await self.registerPushIfSignedIn()
                } else {
                    self.userProfile = nil
                }
            }
        }

        contactManager.requestAccessToContactStore()
    }

    // MARK: - Async API

    func signIn(email: String, password: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else {
            throw AppError.validation(String(localized: "error.auth.missing", defaultValue: "Enter your email and password."))
        }
        let authUser = try await authService.signIn(email: email, password: password)
        guard let account = try await userRepository.account(id: authUser.id) else {
            // Authenticated but profile missing: don't leave a half-signed-in session.
            try? authService.signOut()
            throw AppError.notFound
        }
        userProfile = account
        prepareLocalStore(for: account)
        await syncContacts()
    }

    func signUp(email: String, password: String, phoneNumber: Int64, displayName: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !name.isEmpty, phoneNumber > 0 else {
            throw AppError.validation(String(localized: "error.auth.incomplete", defaultValue: "Please fill in all fields."))
        }
        let authUser = try await authService.register(email: email, password: password)
        let account = UserAccount(id: authUser.id, email: email, displayName: name,
                                  phoneNumber: phoneNumber, photoURL: nil, createdAt: Date())
        do {
            try await userRepository.save(account)
        } catch {
            // Roll back so the user can retry registration instead of being stuck with an orphan auth user.
            try? await authService.deleteAccount()
            throw error
        }
        // Re-read the stored account: some backends assign their own user id (the MyBuddy API uses a
        // server UUID, not the Firebase uid), and everything local must be keyed by that id.
        let canonical = (try? await userRepository.account(id: authUser.id)) ?? nil
        let stored = canonical ?? account
        userProfile = stored
        prepareLocalStore(for: stored)
        await syncContacts()
        try? await authService.sendEmailVerification()
    }

    func sendPasswordReset(email: String) async throws {
        try await authService.sendPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Re-authenticates first (Firebase requires a recent login), then deletes the account.
    /// NOTE: server-side data (users doc, chats, feed copies, reactions) must be removed by a backend
    /// function triggered by account deletion; the client cannot do it safely.
    func deleteAccount(password: String) async throws {
        try await authService.reauthenticate(password: password)
        if let uid = user?.id { await unregisterPush(uid: uid) }
        try await authService.deleteAccount()
        coreDataUtils.clearCoreData()
        PendingMessageStore.shared.clear()
        UserDefaults.standard.removeObject(forKey: Self.lastUIDKey)
    }

    func logout() {
        let uid = user?.id
        BlockedUsersStore.shared.clear()
        Task {
            // Remove this device's push token while still authenticated (bounded wait; offline must not block logout).
            if let uid { await unregisterPush(uid: uid) }
            coreDataUtils.clearCoreData()
            PendingMessageStore.shared.clear()
            UserDefaults.standard.removeObject(forKey: Self.lastUIDKey)
            do { try authService.signOut() } catch {
                Log.auth.error("signOut failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
            }
        }
    }

    // MARK: - Push

    /// Safe to call repeatedly (sign-in, token refresh). The system permission prompt appears once.
    func registerPushIfSignedIn() async {
        guard let uid = user?.id else { return }
        do {
            if try await pushService.requestAuthorization() {
                try await pushService.registerDevice(userID: uid)
            }
        } catch {
            Log.auth.error("push registration failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
        }
    }

    private func unregisterPush(uid: String) async {
        let service = pushService
        await withTimeout(seconds: 3) { try? await service.unregisterDevice(userID: uid) }
    }

    // MARK: - Completion-handler wrappers (existing call sites)

    func login(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Task {
            do { try await signIn(email: email, password: password); completion(nil) }
            catch { completion(AppError.wrap(error)) }
        }
    }

    func register(email: String, password: String, phoneNumber: Int64, displayName: String,
                  completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await signUp(email: email, password: password, phoneNumber: phoneNumber, displayName: displayName)
                completion(nil)
            } catch { completion(AppError.wrap(error)) }
        }
    }

    // MARK: - Private

    private func refreshProfile(uid: String) async {
        do { userProfile = try await userRepository.account(id: uid) }
        catch { Log.auth.error("profile refresh failed: \(AppError.wrap(error).diagnostic, privacy: .public)") }
    }

    /// Clears the local cache only when a *different* account signs in, so a
    /// returning user keeps their outbox of unsent messages.
    private func prepareLocalStore(for account: UserAccount) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.lastUIDKey) != account.id {
            coreDataUtils.clearCoreData()
            defaults.set(account.id, forKey: Self.lastUIDKey)
        }
        let profile = UserProfile(account: account)
        coreDataUtils.insertUserProfile(user: profile)
        coreDataUtils.insertContacts(contacts: [profile])
    }

    private func syncContacts() async {
        // Address-book enumeration is blocking I/O: keep it off the main actor.
        let raw = await Task.detached(priority: .utility) { ContactManager().loadContacts() }.value
        let numbers = raw.compactMap { Int64($0) }
        do {
            let matches = try await userRepository.syncContacts(phoneNumbers: numbers)
            coreDataUtils.insertContacts(contacts: matches.map(UserProfile.init(account:)))
        } catch {
            // Contact matching is best-effort; it must not block sign-in.
            Log.auth.error("contact sync failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
        }
    }
}
