//
//  Log.swift
//  MyBuddy
//
//  Thin wrapper over os.Logger. Never pass tokens, passwords, or message
//  bodies. Interpolated values are private by default in release builds.
//

import OSLog

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "MyBuddy"
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let chat = Logger(subsystem: subsystem, category: "chat")
    static let feed = Logger(subsystem: subsystem, category: "feed")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let app = Logger(subsystem: subsystem, category: "app")
}

/// Console logging that is compiled out of release builds (nothing reaches device logs in production).
/// Never pass tokens, passwords or message content.
@inlinable func debugLog(_ items: Any...) {
    #if DEBUG
    print(items.map { "\($0)" }.joined(separator: " "))
    #endif
}

/// Legal / support URLs come from Info.plist (`MBTermsURL`, `MBPrivacyPolicyURL`, `MBSupportURL`).
/// A missing or non-HTTPS value hides the link instead of shipping a dead one.
enum LegalLinks {
    static var terms: URL? { url(for: "MBTermsURL") }
    static var privacyPolicy: URL? { url(for: "MBPrivacyPolicyURL") }
    static var support: URL? { url(for: "MBSupportURL") }

    private static func url(for key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }
}

extension URL {
    /// Only plain web links from user-generated text; never custom schemes, tel:, file:, etc.
    static func safeWebLink(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}
