//
//  MyBuddyTests.swift
//  MyBuddyTests
//
//  Unit tests run against mock implementations only; no Firebase access.
//

import XCTest
@testable import MyBuddy

final class AppErrorTests: XCTestCase {
    func testWrapPreservesAppErrorAndMapsCancellation() {
        XCTAssertEqual(AppError.wrap(CancellationError()).isRetryable, false)
        if case .cancelled = AppError.wrap(CancellationError()) {} else { XCTFail("expected cancelled") }
        if case .permission = AppError.wrap(AppError.permission) {} else { XCTFail("expected permission") }
    }

    func testRetryability() {
        XCTAssertTrue(AppError.network(underlying: "x").isRetryable)
        XCTAssertFalse(AppError.permission.isRetryable)
        XCTAssertFalse(AppError.authentication(.invalidCredentials).isRetryable)
    }

    func testUserMessageNeverLeaksDiagnostics() {
        let e = AppError.backend(underlying: "firestore:14 secret-internal-detail")
        XCTAssertFalse(e.userMessage.contains("secret-internal-detail"))
        XCTAssertTrue(e.diagnostic.contains("secret-internal-detail"))
    }
}

final class ConfigurationTests: XCTestCase {
    func testUITestingFlagSelectsMockBackend() {
        let config = AppConfiguration.current(processEnvironment: ["MBUITesting": "1"])
        XCTAssertEqual(config.backend, .mock)
        XCTAssertEqual(config.environment, .test)
    }
}

final class DomainModelTests: XCTestCase {
    func testOtherParticipantHandlesMalformedConversation() {
        let c = Conversation(id: "c", participants: ["me"], lastMessage: "", lastSenderID: "", lastType: "text",
                             updatedAt: Date(), currentUserPhoneNumber: 0, recipientUserPhoneNumber: 0, lastSenderPhoneNumber: 0)
        XCTAssertNil(c.otherParticipant(than: "me"))
    }

    func testLegacyChatMsgRecipientIsTheOtherParticipant() {
        // Regression: previously returned the current user when they were participants[0].
        let a = FirebaseChatMsg(from: ["participants": ["a", "b"]], id: "c", currentUserId: "a")
        let b = FirebaseChatMsg(from: ["participants": ["a", "b"]], id: "c", currentUserId: "b")
        XCTAssertEqual(a.recipientUserId, "b")
        XCTAssertEqual(b.recipientUserId, "a")
        // and no longer traps on malformed data
        XCTAssertEqual(FirebaseChatMsg(from: [:], id: "c", currentUserId: "a").recipientUserId, "")
    }
}

final class MockAuthenticationTests: XCTestCase {
    func testRegisterSignOutSignIn() async throws {
        let auth = MockAuthenticationService()
        _ = try await auth.register(email: "a@b.com", password: "secret1")
        try auth.signOut()
        XCTAssertNil(auth.currentUser)
        let user = try await auth.signIn(email: "a@b.com", password: "secret1")
        XCTAssertEqual(auth.currentUser, user)
    }

    func testInvalidCredentials() async {
        let auth = MockAuthenticationService()
        do { _ = try await auth.signIn(email: "x@y.com", password: "nope"); XCTFail("should throw") }
        catch AppError.authentication(let f) { XCTAssertEqual(f, .invalidCredentials) }
        catch { XCTFail("wrong error \(error)") }
    }

    func testDuplicateRegistrationAndWeakPassword() async throws {
        let auth = MockAuthenticationService()
        _ = try await auth.register(email: "a@b.com", password: "secret1")
        do { _ = try await auth.register(email: "a@b.com", password: "secret1"); XCTFail() }
        catch AppError.authentication(let f) { XCTAssertEqual(f, .emailInUse) }
        do { _ = try await auth.register(email: "c@d.com", password: "123"); XCTFail() }
        catch AppError.authentication(let f) { XCTAssertEqual(f, .weakPassword) }
    }

    func testDeleteAccountRequiresSession() async {
        let auth = MockAuthenticationService()
        do { try await auth.deleteAccount(); XCTFail() }
        catch AppError.authentication(let f) { XCTAssertEqual(f, .notSignedIn) }
        catch { XCTFail("wrong error") }
    }
}

final class MockUserRepositoryTests: XCTestCase {
    func testPhoneMatchingDeduplicatesAndFilters() async throws {
        let u = UserAccount(id: "1", email: "e", displayName: "A", phoneNumber: 111, photoURL: nil, createdAt: Date())
        let repo = MockUserRepository([u])
        let found = try await repo.accounts(matchingPhoneNumbers: [111, 111, 222])
        XCTAssertEqual(found.map(\.id), ["1"])
    }
}

final class MockChatRepositoryTests: XCTestCase {
    private func outgoing(_ id: String, chat: String = "c") -> OutgoingMessage {
        OutgoingMessage(id: id, conversationID: chat, senderID: "a", recipientID: "b", content: "hi \(id)",
                        type: "text", mediaURL: "", senderPhoneNumber: 1, recipientPhoneNumber: 2)
    }

    func testSendIsIdempotent() async throws {
        let repo = MockChatRepository()
        try await repo.send(outgoing("m1"))
        try await repo.send(outgoing("m1"))   // retry after a lost response
        XCTAssertEqual(repo.messageCount("c"), 1)
        XCTAssertEqual(repo.sendAttempts, 2)
    }

    func testFailedSendPropagatesRetryableError() async {
        let repo = MockChatRepository()
        repo.sendError = .network(underlying: "offline")
        do { try await repo.send(outgoing("m1")); XCTFail() }
        catch let e as AppError { XCTAssertTrue(e.isRetryable) }
        catch { XCTFail("wrong error") }
        XCTAssertEqual(repo.messageCount("c"), 0)
    }

    func testCursorPagination() async throws {
        let repo = MockChatRepository()
        for i in 0..<5 {
            try await repo.send(outgoing("m\(i)"))
            try await Task.sleep(nanoseconds: 3_000_000)
        }
        var latest: [ChatMessage] = []
        for try await batch in repo.observeLatestMessages(conversationID: "c", limit: 2) { latest = batch; break }
        XCTAssertEqual(latest.map(\.id), ["m4", "m3"])

        let cursor = MessageCursor(timestamp: latest.last!.timestamp, id: latest.last!.id)
        let page = try await repo.loadOlderMessages(conversationID: "c", before: cursor, limit: 2)
        XCTAssertEqual(page.messages.map(\.id), ["m2", "m1"])
        XCTAssertNotNil(page.nextCursor)
        let last = try await repo.loadOlderMessages(conversationID: "c", before: page.nextCursor!, limit: 2)
        XCTAssertEqual(last.messages.map(\.id), ["m0"])
        XCTAssertNil(last.nextCursor)
    }

    func testCancellingConsumerRemovesListener() async throws {
        let repo = MockChatRepository()
        let task = Task { for try await _ in repo.observeLatestMessages(conversationID: "c", limit: 10) {} }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(repo.activeMessageObservers, 1)
        task.cancel()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(repo.activeMessageObservers, 0)
    }

    func testObserverReceivesNewMessage() async throws {
        let repo = MockChatRepository()
        let received = expectation(description: "message delivered")
        let task = Task {
            for try await batch in repo.observeLatestMessages(conversationID: "c", limit: 10) where !batch.isEmpty {
                received.fulfill(); break
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        try await repo.send(outgoing("m1"))
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
    }
}

final class MockFeedRepositoryTests: XCTestCase {
    private func post(_ id: String = "p1") -> NewPost {
        NewPost(id: id, authorID: "u1", authorPhone: 100, content: "hello")
    }

    func testPublishIncludesAuthorAndIsIdempotent() async throws {
        let repo = MockFeedRepository()
        try await repo.publish(post(), recipientPhones: [200, 300, 200])
        try await repo.publish(post(), recipientPhones: [200, 300])     // retry
        XCTAssertEqual(repo.copies(of: "p1"), 3)                         // author + 2 recipients, no duplicates
        var own: [FeedPost] = []
        for try await batch in repo.observeFeed(ownerPhone: 100, limit: 10) { own = batch; break }
        XCTAssertEqual(own.map(\.id), ["p1"])
    }

    func testPublishFailureIsRetryable() async {
        let repo = MockFeedRepository()
        repo.publishError = .network(underlying: "offline")
        do { try await repo.publish(post(), recipientPhones: []); XCTFail() }
        catch let e as AppError { XCTAssertTrue(e.isRetryable) }
        catch { XCTFail("wrong error") }
        XCTAssertEqual(repo.copies(of: "p1"), 0)
    }

    func testOneReactionPerUserAndRemoval() async throws {
        let repo = MockFeedRepository()
        try await repo.setReaction(postID: "p1", userID: "a", reaction: .like)
        try await repo.setReaction(postID: "p1", userID: "b", reaction: .dislike)
        try await repo.setReaction(postID: "p1", userID: "a", reaction: .dislike)   // switch, not add
        var s = try await repo.reactionSummary(postID: "p1", userID: "a")
        XCTAssertEqual(s, ReactionSummary(likes: 0, dislikes: 2, mine: .dislike))
        try await repo.setReaction(postID: "p1", userID: "a", reaction: nil)
        s = try await repo.reactionSummary(postID: "p1", userID: "a")
        XCTAssertEqual(s, ReactionSummary(likes: 0, dislikes: 1, mine: nil))
    }
}

final class MockReauthTests: XCTestCase {
    func testReauthenticateChecksPassword() async throws {
        let auth = MockAuthenticationService()
        _ = try await auth.register(email: "a@b.com", password: "secret1")
        try await auth.reauthenticate(password: "secret1")
        do { try await auth.reauthenticate(password: "wrong"); XCTFail() }
        catch AppError.authentication(let f) { XCTAssertEqual(f, .invalidCredentials) }
    }
}

final class DeepLinkTests: XCTestCase {
    private func link(_ s: String) -> DeepLink? { URL(string: s).flatMap(DeepLink.init(url:)) }

    func testValidLinks() {
        XCTAssertEqual(link("mybuddy://chat/2348011_2348022"), .chat(conversationID: "2348011_2348022"))
        XCTAssertEqual(link("mybuddy://profile/uid-123"), .profile(userID: "uid-123"))
        XCTAssertEqual(link("MYBUDDY://Post/abc"), .post(postID: "abc"))
    }

    func testMalformedLinksAreRejected() {
        XCTAssertNil(link("https://chat/abc"))                 // wrong scheme
        XCTAssertNil(link("mybuddy://chat"))                   // missing id
        XCTAssertNil(link("mybuddy://chat/a/b"))               // extra segment
        XCTAssertNil(link("mybuddy://settings/abc"))           // unknown host
        XCTAssertNil(link("mybuddy://chat/a%20b"))             // disallowed character
        XCTAssertNil(link("mybuddy://chat/..%2F..%2Fusers"))   // traversal attempt
        XCTAssertNil(link("mybuddy://chat/" + String(repeating: "a", count: 129)))
    }

    func testNotificationPayload() {
        XCTAssertEqual(DeepLink(userInfo: ["deepLink": "mybuddy://chat/c1"]), .chat(conversationID: "c1"))
        XCTAssertEqual(DeepLink(userInfo: ["chatId": "c2"]), .chat(conversationID: "c2"))
        XCTAssertNil(DeepLink(userInfo: ["deepLink": "mybuddy://chat/bad id"]))
        XCTAssertNil(DeepLink(userInfo: ["unrelated": 1]))
    }
}

@MainActor
final class DeepLinkRouterTests: XCTestCase {
    func testColdLaunchLinkWaitsUntilConsumed() {
        let router = DeepLinkRouter()
        router.handle(url: URL(string: "mybuddy://chat/c1")!)       // arrives before any UI exists
        XCTAssertEqual(router.pending, .chat(conversationID: "c1"))
        router.routePendingToTab()
        XCTAssertEqual(router.selectedTab, .chats)
        XCTAssertEqual(router.pending, .chat(conversationID: "c1")) // chat list still has to open it
        XCTAssertEqual(router.consume(), .chat(conversationID: "c1"))
        XCTAssertNil(router.pending)
    }

    func testProfileAndPostSelectTabAndAreConsumed() {
        let router = DeepLinkRouter()
        router.handle(.post(postID: "p"))
        router.routePendingToTab()
        XCTAssertEqual(router.selectedTab, .feed)
        XCTAssertNil(router.pending)
        router.handle(.profile(userID: "u"))
        router.routePendingToTab()
        XCTAssertEqual(router.selectedTab, .contacts)
    }

    func testMalformedURLDoesNotReplacePendingLink() {
        let router = DeepLinkRouter()
        router.handle(.chat(conversationID: "c1"))
        router.handle(url: URL(string: "mybuddy://nonsense/x")!)
        XCTAssertEqual(router.pending, .chat(conversationID: "c1"))
    }
}

final class TimeoutAndPushTests: XCTestCase {
    func testWithTimeoutReturnsWhenOperationHangs() async {
        let start = Date()
        await withTimeout(seconds: 0.2) { try? await Task.sleep(nanoseconds: 5_000_000_000) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testWithTimeoutReturnsEarlyWhenOperationFinishes() async {
        let start = Date()
        await withTimeout(seconds: 5) {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testDeviceRegistrationLifecycle() async throws {
        let push = MockPushNotificationService()
        let granted = try await push.requestAuthorization()
        XCTAssertTrue(granted)
        try await push.registerDevice(userID: "u1")
        XCTAssertTrue(push.isRegistered("u1"))
        try await push.unregisterDevice(userID: "u1")
        XCTAssertFalse(push.isRegistered("u1"))
    }
}

final class ImageProcessorTests: XCTestCase {
    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        }
    }

    func testLargeImageIsDownscaledPreservingAspectRatio() async throws {
        let prepared = await ImageProcessor.prepare(makeImage(width: 4000, height: 3000), maxDimension: 1600)
        let processed = try XCTUnwrap(prepared)
        XCTAssertEqual(processed.pixelWidth, 1600)
        XCTAssertEqual(processed.pixelHeight, 1200)
        let decoded = try XCTUnwrap(UIImage(data: processed.data))
        XCTAssertEqual(max(decoded.size.width * decoded.scale, decoded.size.height * decoded.scale), 1600, accuracy: 1)
    }

    func testSmallImageIsNeverUpscaled() async throws {
        let prepared = await ImageProcessor.prepare(makeImage(width: 300, height: 200), maxDimension: 1600)
        let processed = try XCTUnwrap(prepared)
        XCTAssertEqual(processed.pixelWidth, 300)
        XCTAssertEqual(processed.pixelHeight, 200)
    }

    func testDownsampleBoundsDecodedSize() throws {
        let data = try XCTUnwrap(makeImage(width: 3000, height: 2000).jpegData(compressionQuality: 0.9))
        let thumb = try XCTUnwrap(ImageProcessor.downsample(data: data, maxPixel: 400))
        XCTAssertLessThanOrEqual(max(thumb.size.width * thumb.scale, thumb.size.height * thumb.scale), 400)
    }

    func testMemoryCacheReturnsSameInstanceForSameKey() throws {
        let data = try XCTUnwrap(makeImage(width: 800, height: 600).jpegData(compressionQuality: 0.9))
        let a = ImageMemoryCache.shared.image(key: "k1", data: data, maxPixel: 200)
        let b = ImageMemoryCache.shared.image(key: "k1", data: data, maxPixel: 200)
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b)
    }
}

final class MediaTests: XCTestCase {
    func testUploadPathsAreDeterministicPerMessage() {
        XCTAssertEqual(MediaPath.chatImage(userID: "u", messageID: "m"), "chat_images/u/m.jpg")
    }

    func testUploadIsIdempotentAndRetriesAfterFailure() async throws {
        let media = MockMediaRepository()
        media.failuresRemaining = 1
        let path = MediaPath.chatImage(userID: "u", messageID: "m1")
        do { _ = try await media.uploadImage(Data([1]), path: path, onProgress: nil); XCTFail() }
        catch let e as AppError { XCTAssertTrue(e.isRetryable) }
        let first = try await media.uploadImage(Data([1]), path: path, onProgress: nil)
        let second = try await media.uploadImage(Data([1]), path: path, onProgress: nil)   // retry after lost response
        XCTAssertEqual(first, second)
        XCTAssertEqual(media.storedCount, 1)
    }

    func testOutgoingMessageWithMediaKeepsEverythingElse() {
        let m = OutgoingMessage(id: "i", conversationID: "c", senderID: "s", recipientID: "r", content: "hi",
                                type: "image", mediaURL: "", senderPhoneNumber: 1, recipientPhoneNumber: 2)
        let updated = m.with(media: UploadedMedia(id: "media-1", url: "https://x/y.jpg"))
        XCTAssertEqual(updated.mediaURL, "https://x/y.jpg")
        XCTAssertEqual(updated.mediaID, "media-1")
        XCTAssertEqual(updated.id, "i")
        XCTAssertEqual(updated.content, "hi")
        XCTAssertEqual(updated.type, "image")
    }

    func testPhotoURLUpdateAndRemoval() async throws {
        let user = UserAccount(id: "1", email: "e", displayName: "A", phoneNumber: 5, photoURL: nil, createdAt: Date())
        let repo = MockUserRepository([user])
        try await repo.updatePhoto(id: "1", media: UploadedMedia(id: "m", url: "https://x/a.jpg"))
        var current = try await repo.account(id: "1")
        XCTAssertEqual(current?.photoURL, "https://x/a.jpg")
        try await repo.updatePhoto(id: "1", media: nil)
        current = try await repo.account(id: "1")
        XCTAssertNil(current?.photoURL)
    }

    func testMediaDownloaderRejectsNonHTTPS() async {
        do { _ = try await MediaDownloader.data(from: "http://example.com/a.jpg"); XCTFail() }
        catch AppError.validation {} catch { XCTFail("wrong error \(error)") }
    }
}

import CoreData

final class DeliveryStateTests: XCTestCase {
    func testResolvePrefersServerAcknowledgement() {
        XCTAssertEqual(DeliveryState.resolve(sent: true, rawState: DeliveryState.failed.rawValue), .sent)
        XCTAssertEqual(DeliveryState.resolve(sent: false, rawState: DeliveryState.failed.rawValue), .failed)
        XCTAssertEqual(DeliveryState.resolve(sent: false, rawState: 0), .sending)
        XCTAssertEqual(DeliveryState.resolve(sent: false, rawState: 99), .sending)   // unknown value never hides a message
    }
}

final class CoreDataModelTests: XCTestCase {
    @MainActor
    func testModelIsVersion2AndPersistsDeliveryState() throws {
        let container = PersistenceController.preview.container
        XCTAssertTrue(container.managedObjectModel.versionIdentifiers.contains("2" as AnyHashable))

        let context = container.viewContext
        let id = "test-\(UUID().uuidString)"
        let message = Message(context: context)
        message.id = id
        message.sent = false
        message.deliveryState = DeliveryState.failed.rawValue
        try context.save()

        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND deliveryState == %ld", id, Int(DeliveryState.failed.rawValue))
        XCTAssertEqual(try context.fetch(request).count, 1)

        context.delete(message)
        try context.save()
    }
}

final class EnvironmentResolutionTests: XCTestCase {
    func testUITestingWinsOverEverything() {
        let c = AppConfiguration.current(processEnvironment: ["MBUITesting": "1", "MBEnvironment": "production"])
        XCTAssertEqual(c.environment, .test)
        XCTAssertEqual(c.backend, .mock)
    }

    func testUnexpandedBuildSettingFallsBack() {
        // Info.plist of the test bundle has no usable value; must not crash or pick garbage.
        let c = AppConfiguration.current(processEnvironment: [:])
        XCTAssertEqual(c.backend, .firebase)
        XCTAssertNotEqual(c.environment, .test)
    }

    #if DEBUG
    func testDebugBuildsHonorSchemeOverrideAndEmulatorHost() {
        let c = AppConfiguration.current(processEnvironment: ["MBEnvironment": "staging", "MBFirebaseEmulatorHost": "localhost"])
        XCTAssertEqual(c.environment, .staging)
        XCTAssertEqual(c.emulatorHost, "localhost")
    }

    func testInvalidOverrideIsIgnored() {
        let c = AppConfiguration.current(processEnvironment: ["MBEnvironment": "banana"])
        XCTAssertNotEqual(c.environment, .test)
        XCTAssertNil(c.emulatorHost)
    }
    #endif
}

final class SafetyTests: XCTestCase {
    private func other() -> BlockedUser {
        BlockedUser(id: "u2", phoneNumber: 222, displayName: "Bob", blockedAt: Date())
    }

    @MainActor
    func testBlockHidesImmediatelyAndUnblockRestores() async throws {
        let repo = MockSafetyRepository()
        let store = BlockedUsersStore(repository: repo)
        let sync = Task { await store.sync(userID: "u1") }
        try await Task.sleep(nanoseconds: 50_000_000)
        try await store.block(other())
        XCTAssertTrue(store.isBlocked(userID: "u2"))
        XCTAssertEqual(store.phones, [222])
        try await store.unblock(userID: "u2")
        XCTAssertFalse(store.isBlocked(userID: "u2"))
        sync.cancel()
    }

    @MainActor
    func testCannotBlockSelfOrActWhenSignedOut() async {
        let store = BlockedUsersStore(repository: MockSafetyRepository())
        do { try await store.block(other()); XCTFail() }
        catch AppError.authentication(let f) { XCTAssertEqual(f, .notSignedIn) }
        catch { XCTFail("wrong error") }
    }

    @MainActor
    func testReportIsRecorded() async throws {
        let repo = MockSafetyRepository()
        let store = BlockedUsersStore(repository: repo)
        let sync = Task { await store.sync(userID: "u1") }
        try await Task.sleep(nanoseconds: 50_000_000)
        try await store.report(userID: "u2", reason: .harassment, conversationID: "c")
        XCTAssertEqual(repo.reportCount, 1)
        sync.cancel()
    }
}

final class LinkSafetyTests: XCTestCase {
    func testOnlyWebLinksFromUserText() {
        XCTAssertNotNil(URL.safeWebLink("https://example.com/a"))
        XCTAssertNotNil(URL.safeWebLink("http://example.com"))
        XCTAssertNil(URL.safeWebLink("tel:+2348000000"))
        XCTAssertNil(URL.safeWebLink("mybuddy://chat/abc"))
        XCTAssertNil(URL.safeWebLink("javascript:alert(1)"))
        XCTAssertNil(URL.safeWebLink("not a url"))
        XCTAssertNil(URL.safeWebLink(""))
    }
}
