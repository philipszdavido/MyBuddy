//
//  DeepLink.swift
//  MyBuddy
//
//  Parsed, validated navigation intents. Only strictly formed links are accepted;
//  anything else (unknown host, extra path segments, odd characters) is ignored.
//
//    mybuddy://chat/{conversationId}
//    mybuddy://profile/{userId}
//    mybuddy://post/{postId}
//

import Foundation

enum DeepLink: Equatable, Sendable {
    case chat(conversationID: String)
    case profile(userID: String)
    case post(postID: String)

    static let scheme = "mybuddy"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let host = url.host?.lowercased() else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.count == 1, Self.isValidID(segments[0]) else { return nil }
        let id = segments[0]
        switch host {
        case "chat": self = .chat(conversationID: id)
        case "profile": self = .profile(userID: id)
        case "post": self = .post(postID: id)
        default: return nil
        }
    }

    /// Notification payload: `deepLink` (URL string) or legacy `chatId`.
    init?(userInfo: [AnyHashable: Any]) {
        if let raw = userInfo["deepLink"] as? String, let url = URL(string: raw), let link = DeepLink(url: url) {
            self = link
        } else if let chatID = userInfo["chatId"] as? String, Self.isValidID(chatID) {
            self = .chat(conversationID: chatID)
        } else {
            return nil
        }
    }

    /// ASCII letters, digits, `_` and `-`, 1...128 characters.
    static func isValidID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy { s in
            switch s.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2D: return true
            default: return false
            }
        }
    }
}
