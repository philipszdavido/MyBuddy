//
//  DeepLinkRouter.swift
//  MyBuddy
//
//  Single entry point for URLs and notification taps. A link that arrives before the UI is ready
//  (cold launch) simply waits in `pending` until the signed-in UI consumes it.
//

import Foundation

enum AppTab: Int, Hashable {
    case chats, feed, contacts, settings
}

@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published private(set) var pending: DeepLink?
    @Published var selectedTab: AppTab = .chats
    /// Conversation currently on screen; used to suppress foreground banners for it.
    var activeChatID: String?
    /// When the feed can show profiles and posts itself (MyBuddy API backend), those links stay pending
    /// for it to open; otherwise they only switch tabs.
    var feedHandlesProfileAndPostLinks = false

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else {
            Log.app.notice("ignored malformed deep link")
            return
        }
        pending = link
    }

    func handle(_ link: DeepLink?) {
        if let link { pending = link }
    }

    @discardableResult
    func consume() -> DeepLink? {
        defer { pending = nil }
        return pending
    }

    /// Switches tab for the pending link. Profile and post links have no dedicated screen yet, so they
    /// land on the matching tab and are consumed; chat links stay pending for the chat list to open.
    func routePendingToTab() {
        switch pending {
        case .chat?: selectedTab = .chats
        case .profile?:
            if feedHandlesProfileAndPostLinks { selectedTab = .feed } else { selectedTab = .contacts; consume() }
        case .post?:
            selectedTab = .feed
            if !feedHandlesProfileAndPostLinks { consume() }
        case nil: break
        }
    }
}
