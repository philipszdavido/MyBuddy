//
//  FirebaseErrorMapper.swift
//  MyBuddy
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

enum FirebaseErrorMapper {
    static func map(_ error: Error) -> AppError {
        if let e = error as? AppError { return e }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError

        if ns.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: ns.code) {
            switch code {
            case .wrongPassword, .invalidCredential, .userNotFound: return .authentication(.invalidCredentials)
            case .emailAlreadyInUse: return .authentication(.emailInUse)
            case .weakPassword: return .authentication(.weakPassword)
            case .invalidEmail: return .authentication(.invalidEmail)
            case .userDisabled: return .authentication(.accountDisabled)
            case .userTokenExpired, .invalidUserToken: return .authentication(.sessionExpired)
            case .requiresRecentLogin: return .authentication(.requiresRecentLogin)
            case .networkError: return .network(underlying: ns.localizedDescription)
            default: return .backend(underlying: "auth:\(ns.code)")
            }
        }

        if ns.domain == FirestoreErrorDomain, let code = FirestoreErrorCode.Code(rawValue: ns.code) {
            switch code {
            case .permissionDenied: return .permission
            case .unauthenticated: return .authentication(.sessionExpired)
            case .notFound: return .notFound
            case .unavailable, .deadlineExceeded: return .network(underlying: ns.localizedDescription)
            case .cancelled: return .cancelled
            default: return .backend(underlying: "firestore:\(ns.code)")
            }
        }

        if ns.domain == StorageErrorDomain, let code = StorageErrorCode(rawValue: ns.code) {
            switch code {
            case .objectNotFound: return .notFound
            case .unauthenticated: return .authentication(.sessionExpired)
            case .unauthorized: return .permission
            case .cancelled: return .cancelled
            case .retryLimitExceeded: return .network(underlying: "storage retry limit")
            default: return .storage(underlying: "storage:\(ns.code)")
            }
        }

        if ns.domain == NSURLErrorDomain { return AppError.wrap(error) }
        return .unknown(underlying: "\(ns.domain):\(ns.code)")
    }
}
