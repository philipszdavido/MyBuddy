//
//  AppConfiguration.swift
//  MyBuddy
//
//  Environment + backend selection. Only the composition root reads this.
//

import Foundation

enum AppEnvironment: String, Sendable {
    case development, staging, production, test
}

enum BackendKind: String, Sendable {
    case firebase
    case mock
    /// MyBuddy API (NestJS/PostgreSQL/Redis/R2). Firebase stays the identity provider and push transport.
    case api
}

struct FeatureFlags: Sendable {
    var mediaMessages = true
    var feedComments = false
    /// Reserved for the AI Buddy feature (code is compiled out until `AI_BUDDY` is defined and a server-side proxy exists).
    var aiBuddy = false
}

struct AppConfiguration: Sendable {
    let environment: AppEnvironment
    let backend: BackendKind
    let features: FeatureFlags
    /// Host of the Firebase Emulator Suite (development only, DEBUG builds only), e.g. "localhost".
    let emulatorHost: String?
    /// Base URL of the MyBuddy API (no /api/v1 suffix). When set, the app uses the `.api` backend.
    let apiBaseURL: URL?

    init(environment: AppEnvironment, backend: BackendKind, features: FeatureFlags, emulatorHost: String? = nil, apiBaseURL: URL? = nil) {
        self.environment = environment
        self.backend = backend
        self.features = features
        self.emulatorHost = emulatorHost
        self.apiBaseURL = apiBaseURL
    }

    /// Resolution order:
    ///  1. `MBUITesting=1` (launch environment)  -> test + mock backend
    ///  2. DEBUG only: `MBEnvironment` launch environment variable (Xcode scheme) overrides everything below
    ///  3. Info.plist `MBEnvironment` (set from the `MB_ENVIRONMENT` build setting)
    ///  4. fallback: development for DEBUG, production otherwise
    /// Backend: `.api` when an API base URL is configured (Info.plist `MBAPIBaseURL`, from the
    /// `MB_API_BASE_URL` build setting; DEBUG builds may override it with the `MBAPIBaseURL` launch
    /// variable), otherwise `.firebase`.
    /// Release builds ignore launch-environment overrides so a shipped binary cannot be redirected.
    static func current(
        bundle: Bundle = .main,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppConfiguration {
        if processEnvironment["MBUITesting"] == "1" {
            return AppConfiguration(environment: .test, backend: .mock, features: FeatureFlags())
        }

        #if DEBUG
        let fallback = AppEnvironment.development
        let override = processEnvironment["MBEnvironment"].flatMap(AppEnvironment.init(rawValue:))
        let emulatorHost = processEnvironment["MBFirebaseEmulatorHost"].flatMap { $0.isEmpty ? nil : $0 }
        let apiOverride = processEnvironment["MBAPIBaseURL"].flatMap(Self.apiURL)
        #else
        let fallback = AppEnvironment.production
        let override: AppEnvironment? = nil
        let emulatorHost: String? = nil
        let apiOverride: URL? = nil
        #endif
        let apiBaseURL = apiOverride ?? (bundle.object(forInfoDictionaryKey: "MBAPIBaseURL") as? String).flatMap(Self.apiURL)

        // An unexpanded "$(MB_ENVIRONMENT)" simply fails to parse and falls through.
        let plistValue = (bundle.object(forInfoDictionaryKey: "MBEnvironment") as? String)
            .flatMap(AppEnvironment.init(rawValue:))
        let environment = override ?? plistValue ?? fallback

        return AppConfiguration(environment: environment, backend: apiBaseURL == nil ? .firebase : .api, features: FeatureFlags(),
                                emulatorHost: emulatorHost, apiBaseURL: apiBaseURL)
    }

    /// Accepts only absolute http(s) URLs; an unexpanded "$(MB_API_BASE_URL)" or empty value means "not set".
    /// Plain http is allowed only for local development hosts.
    static func apiURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), let host = url.host, !host.isEmpty else { return nil }
        switch url.scheme {
        case "https": return url
        case "http": return ["localhost", "127.0.0.1"].contains(host) || host.hasSuffix(".local") ? url : nil
        default: return nil
        }
    }
}
