//
//  FirebaseAuthenticationService.swift
//  MyBuddy
//

import Foundation
import FirebaseAuth

final class FirebaseAuthenticationService: AuthenticationService, @unchecked Sendable {
    // FirebaseAuth is thread-safe; @unchecked is only because Auth isn't marked Sendable.
    private let auth: Auth

    init(auth: Auth = Auth.auth()) { self.auth = auth }

    private static func map(_ user: User) -> AuthUser {
        AuthUser(id: user.uid, email: user.email, isEmailVerified: user.isEmailVerified)
    }

    var currentUser: AuthUser? { auth.currentUser.map(Self.map) }

    func authStateChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            let handle = auth.addStateDidChangeListener { _, user in
                continuation.yield(user.map(Self.map))
            }
            continuation.onTermination = { [auth] _ in
                auth.removeStateDidChangeListener(handle)
            }
        }
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            return Self.map(result.user)
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    func reauthenticate(password: String) async throws {
        guard let user = auth.currentUser, let email = user.email else {
            throw AppError.authentication(.notSignedIn)
        }
        do {
            try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    func register(email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            return Self.map(result.user)
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    func sendPasswordReset(email: String) async throws {
        do { try await auth.sendPasswordReset(withEmail: email) }
        catch { throw FirebaseErrorMapper.map(error) }
    }

    func sendEmailVerification() async throws {
        guard let user = auth.currentUser else { throw AppError.authentication(.notSignedIn) }
        do { try await user.sendEmailVerification() }
        catch { throw FirebaseErrorMapper.map(error) }
    }

    func signOut() throws {
        do { try auth.signOut() } catch { throw FirebaseErrorMapper.map(error) }
    }

    func idToken(forceRefresh: Bool) async throws -> String {
        guard let user = auth.currentUser else { throw AppError.authentication(.notSignedIn) }
        do { return try await user.getIDToken(forcingRefresh: forceRefresh) }
        catch { throw FirebaseErrorMapper.map(error) }
    }

    func deleteAccount() async throws {
        guard let user = auth.currentUser else { throw AppError.authentication(.notSignedIn) }
        do { try await user.delete() } catch { throw FirebaseErrorMapper.map(error) }
    }
}
