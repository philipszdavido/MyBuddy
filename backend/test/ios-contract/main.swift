// Contract test driver: the iOS app's real API layer (MyBuddy/Data/API + Domain), compiled for macOS
// and run against a live backend by test/ios-contract.int.ts. Exits non-zero on the first failure.
//
// Environment: MB_URL, MB_TOKEN_A, MB_TOKEN_B (test tokens), MB_UID_A (Firebase uid of A),
//              MB_ID_B (backend id of B), MB_PHONE_A, MB_PHONE_B.

import Foundation
import ImageIO
import UniformTypeIdentifiers

let env = ProcessInfo.processInfo.environment
func need(_ key: String) -> String { guard let v = env[key] else { fatalError("missing \(key)") }; return v }

let baseURL = URL(string: need("MB_URL"))!
let tokenA = need("MB_TOKEN_A"), tokenB = need("MB_TOKEN_B")
let uidA = need("MB_UID_A"), idB = need("MB_ID_B")
let phoneA = Int64(need("MB_PHONE_A"))!, phoneB = Int64(need("MB_PHONE_B"))!

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "PASS \(what)" : "FAIL \(what)")
    if !ok { failures += 1 }
}

func client(_ token: String) -> (APIClient, RealtimeClient) {
    let provider: @Sendable (Bool) async throws -> String = { _ in token }
    return (APIClient(baseURL: baseURL, tokenProvider: provider), RealtimeClient(baseURL: baseURL, tokenProvider: provider))
}

func jpeg(width: Int, height: Int) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

func run() async throws {
    let (apiA, rtA) = client(tokenA)
    let (apiB, rtB) = client(tokenB)

    // Users: "me" resolves to the backend id; contact sync matches by phone and returns the number.
    let usersA = APIUserRepository(api: apiA, authUID: { uidA })
    let me = try await usersA.account(id: uidA)
    check(me != nil && me!.id != uidA && me!.phoneNumber == phoneA, "users/me maps to a backend id with the phone number")
    let matches = try await usersA.syncContacts(phoneNumbers: [phoneB, 999])
    check(matches.map(\.id) == [idB] && matches.first?.phoneNumber == phoneB, "contact sync returns the matched contact with its phone")
    let lookup = try await usersA.accounts(matchingPhoneNumbers: [phoneB])
    check(lookup.map(\.id) == [idB], "merge lookup returns known contacts")
    let still = try await usersA.syncContacts(phoneNumbers: [phoneB])
    check(still.count == 1, "lookup did not remove contacts")

    // Chat: conversation id, REST send, realtime delivery to the other side, gap-free mapping.
    let chatA = APIChatRepository(api: apiA, realtime: rtA)
    let chatB = APIChatRepository(api: apiB, realtime: rtB)
    let conversation = try await chatA.conversationID(currentUserID: me!.id, currentPhone: phoneA, recipientID: idB, recipientPhone: phoneB)
    check(UUID(uuidString: conversation) != nil, "conversationID returns a server conversation id")

    let received = Task { () -> ChatMessage? in
        var seenInitial = false
        for try await batch in chatB.observeLatestMessages(conversationID: conversation, limit: 50) {
            if !seenInitial { seenInitial = true; continue }  // first emission = history
            if let m = batch.first(where: { $0.content == "hello from swift" }) { return m }
        }
        return nil
    }
    try await Task.sleep(for: .seconds(1.5)) // let B's socket connect
    let clientID = UUID().uuidString
    let outgoing = OutgoingMessage(id: clientID, conversationID: conversation, senderID: me!.id, recipientID: idB,
                                   content: "hello from swift", type: "text", mediaURL: "", senderPhoneNumber: phoneA, recipientPhoneNumber: phoneB)
    try await chatA.send(outgoing)
    try await chatA.send(outgoing) // idempotent resend
    let timeout = Task { try await Task.sleep(for: .seconds(8)); received.cancel() }
    let message = try? await received.value
    timeout.cancel()
    check(message?.id == clientID, "realtime delivered the message to the recipient, keyed by the client id")
    check(message?.senderPhoneNumber == phoneA && message?.recipientID == idB, "message maps phones and recipient for the local store")

    var conversations: [Conversation] = []
    for try await batch in chatB.observeConversations(userID: idB, limit: 20) { conversations = batch; break }
    check(conversations.first?.id == conversation && conversations.first?.lastMessage == "hello from swift", "conversation list shows the last message")
    check(conversations.first?.recipientUserPhoneNumber == phoneA, "conversation maps the contact's phone for the chat list")

    // Social: post, feed, like, comment, media upload with processing, activity.
    let socialA = APISocialRepository(api: apiA)
    let socialB = APISocialRepository(api: apiB)
    let post = try await socialA.createPost(NewPostInput(clientID: UUID().uuidString, text: "from swift #ios", mediaIDs: [], audience: .contacts))
    check(post.canEdit && post.hashtags == ["ios"], "createPost returns the post")
    try await Task.sleep(for: .seconds(1)) // fan-out job
    let feedB = try await socialB.followingFeed(cursor: nil)
    check(feedB.items.contains { $0.id == post.id }, "contact sees the post in the following feed")
    let counts = try await socialB.react(postID: post.id, .like)
    check(counts.likes == 1 && counts.mine == .like, "like returns updated counts")
    let comment = try await socialB.addComment(postID: post.id, text: "nice", parentID: nil, clientID: UUID().uuidString)
    let thread = try await socialA.comments(postID: post.id, cursor: nil)
    check(thread.items.map(\.id) == [comment.id], "comment thread lists the comment")

    let media = try await socialA.uploadMedia(jpeg(width: 1200, height: 800), mimeType: "image/jpeg", purpose: .post)
    check(media.status == .ready && media.urls["medium"] != nil, "presigned upload + processing returns a ready image")
    let photoPost = try await socialA.createPost(NewPostInput(clientID: UUID().uuidString, text: "", mediaIDs: [media.id], audience: .public))
    check(photoPost.kind == "image" && photoPost.media.first?.width == 1200, "photo post carries processed media")

    let chatMedia = try await APIMediaRepository(social: socialA).uploadImage(jpeg(width: 400, height: 300), path: "chat_images/x/y.jpg", onProgress: nil)
    var withMedia = OutgoingMessage(id: UUID().uuidString, conversationID: conversation, senderID: me!.id, recipientID: idB,
                                    content: "", type: "image", mediaURL: chatMedia.url, senderPhoneNumber: phoneA, recipientPhoneNumber: phoneB)
    withMedia.mediaID = chatMedia.id
    try await chatA.send(withMedia)
    check(true, "image message sent with a server media id")

    let activity = try await socialA.activity(cursor: nil)
    check(activity.items.contains { $0.type == .postReaction } && activity.items.contains { $0.type == .comment }, "activity inbox lists the like and the comment")
    let unread = try await socialA.unreadActivityCount()
    try await socialA.markActivityRead(id: nil)
    let after = try await socialA.unreadActivityCount()
    check(unread > 0 && after == 0, "mark all read clears the badge")

    let profile = try await socialB.profile(userID: me!.id)
    check(profile.postsCount == 2 && profile.relationship?.isContact == true && profile.relationship?.following == false, "profile counts and relationship (B has A as a contact, does not follow)")
    let people = try await socialB.searchUsers(me!.displayName, cursor: nil)
    check(people.items.contains { $0.id == me!.id }, "people search finds the user")

    // Account: profile edits (incl. clearing a field), username status, privacy, notification preferences.
    let account = APIAccountRepository(api: apiA, social: socialA)
    let status = try await account.usernameStatus("swiftb")
    check(status == .taken, "username status: taken")
    let invalid = try await account.usernameStatus("no spaces")
    check(invalid == .invalid, "username status: invalid")
    var edited = try await account.update(ProfileChanges(username: "Swift_A2", displayName: nil, bio: "Hello", location: nil, website: "https://example.com", visibility: .private))
    check(edited.username == "swift_a2" && edited.bio == "Hello" && edited.website == "https://example.com" && edited.visibility == .private, "profile update")
    edited = try await account.update(ProfileChanges(username: nil, displayName: nil, bio: "", location: nil, website: "", visibility: .public))
    check(edited.bio == nil && edited.website == nil && edited.visibility == .public, "empty fields clear on the server")
    var privacy = edited.settings
    privacy.sendReadReceipts = false
    privacy.allowMessagesFrom = .connections
    let afterPrivacy = try await account.updatePrivacy(privacy)
    check(afterPrivacy.settings == privacy, "privacy settings round-trip")
    try await account.setNotificationPreference(NotificationPreference(type: .follow, push: false, inApp: true))
    let prefs = try await account.notificationPreferences()
    check(prefs.first { $0.type == .follow }?.push == false && prefs.count >= 10, "notification preferences round-trip")
    let avatar = try await account.setAvatar(jpeg(width: 600, height: 600)) { _ in }
    check(avatar.avatarURL != nil, "avatar upload sets the profile photo")

    // Messaging: groups, rename, send, history, unread.
    let messagingA = APIMessagingRepository(api: apiA, realtime: rtA)
    let messagingB = APIMessagingRepository(api: apiB, realtime: rtB)
    let myID = try await messagingA.currentUserID()
    check(myID == me!.id, "messaging current user id")
    let group = try await messagingA.startConversation(with: [idB], title: nil)
    check(group.kind == .direct && group.id == conversation, "starting a chat with the same person reuses the conversation")
    let sent = try await messagingA.send(conversationID: conversation, clientID: UUID().uuidString, text: "via messaging repo", mediaIDs: [])
    check(sent.text == "via messaging repo" && sent.sender?.id == me!.id, "send returns the message with its sender")
    let history = try await messagingB.messages(conversationID: conversation, beforeSeq: nil, afterSeq: nil)
    check(history.items.first?.clientID == sent.clientID, "history is newest first")
    let inbox = try await messagingB.conversations(requests: false, cursor: nil)
    let row = inbox.items.first { $0.id == conversation }
    check(row != nil && row!.unreadCount > 0 && row!.displayName(me: idB) == me!.displayName, "inbox row: unread count and display name")
    await messagingB.markRead(conversationID: conversation, seq: sent.seq)
    let afterRead = try await messagingB.conversation(id: conversation)
    check(afterRead.unreadCount == 0, "mark read clears unread")
    let contactsB = try await messagingB.contacts()
    check(contactsB.contains { $0.id == me!.id }, "contacts for the new-message picker")
}

let done = DispatchSemaphore(value: 0)
Task {
    do { try await run() } catch {
        print("FAIL unexpected error: \(error)")
        failures += 1
    }
    done.signal()
}
done.wait()
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
