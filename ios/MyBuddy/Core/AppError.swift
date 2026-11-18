//
//  AppError.swift
//  MyBuddy
//
//  Domain error type. Backends map their errors into this; UI never sees raw
//  Firebase/URLSession errors.
//

import Foundation

enum AuthFailure: Sendable, Equatable {
    case invalidCredentials, emailInUse, weakPassword, invalidEmail
    case accountDisabled, sessionExpired, requiresRecentLogin, notSignedIn
}

enum AppError: Error, LocalizedError, Sendable {
    case network(underlying: String)
    case authentication(AuthFailure)
    case permission
    case validation(String)
    case notFound
    case backend(underlying: String)
    case storage(underlying: String)
    case cancelled
    case unknown(underlying: String)

    /// Wraps any error, preserving existing AppErrors and honoring cancellation.
    static func wrap(_ error: Error) -> AppError {
        if let e = error as? AppError { return e }
        if error is CancellationError { return .cancelled }
        if let url = error as? URLError {
            return url.code == .cancelled ? .cancelled : .network(underlying: url.localizedDescription)
        }
        return .unknown(underlying: String(describing: error))
    }

    /// Safe to show users.
    var userMessage: String {
        switch self {
        case .network: return String(localized: "error.network", defaultValue: "You appear to be offline. Check your connection and try again.")
        case .authentication(let f):
            switch f {
            case .invalidCredentials: return String(localized: "error.auth.invalid", defaultValue: "Incorrect email or password.")
            case .emailInUse: return String(localized: "error.auth.emailInUse", defaultValue: "An account with this email already exists.")
            case .weakPassword: return String(localized: "error.auth.weak", defaultValue: "Choose a stronger password (at least 6 characters).")
            case .invalidEmail: return String(localized: "error.auth.email", defaultValue: "Enter a valid email address.")
            case .accountDisabled: return String(localized: "error.auth.disabled", defaultValue: "This account has been disabled.")
            case .sessionExpired, .notSignedIn: return String(localized: "error.auth.session", defaultValue: "Your session has expired. Please sign in again.")
            case .requiresRecentLogin: return String(localized: "error.auth.recent", defaultValue: "Please sign in again to continue.")
            }
        case .permission: return String(localized: "error.permission", defaultValue: "You don't have permission to do that.")
        case .validation(let m): return m
        case .notFound: return String(localized: "error.notFound", defaultValue: "We couldn't find what you were looking for.")
        case .backend, .storage, .unknown: return String(localized: "error.generic", defaultValue: "Something went wrong. Please try again.")
        case .cancelled: return ""
        }
    }

    var errorDescription: String? { userMessage }

    var isRetryable: Bool {
        switch self {
        case .network, .backend, .storage, .unknown: return true
        default: return false
        }
    }

    /// For logs only. May contain backend detail; never show to users.
    var diagnostic: String {
        switch self {
        case .network(let u), .backend(let u), .storage(let u), .unknown(let u): return u
        default: return String(describing: self)
        }
    }
}
