//
//  MyBuddyUITests.swift
//  MyBuddyUITests
//
//  End-to-end flows against the in-memory mock backend (launch environment MBUITesting=1), so these
//  tests never touch Firebase. NOT RUN by the author: element labels were taken from the SwiftUI
//  sources, so expect to adjust a query or two on the first run.
//

import XCTest

final class MyBuddyUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait   // orientation can leak between runs on a cloned simulator
        app = XCUIApplication()
        app.launchEnvironment["MBUITesting"] = "1"

        // The contacts permission prompt can appear at launch; dismiss system alerts so they never block a flow.
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow", "OK", "Don’t Allow", "Don't Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        // Lets the interruption monitor fire. Tap the status-bar area: the screen centre may be a list row.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
    }

    // MARK: Helpers

    private func fill(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "missing field \(field)")
        field.tap()
        if field.elementType == .secureTextField {
            // Secure fields on the simulator drop characters when typed in one burst.
            for character in text { field.typeText(String(character)) }
        } else {
            field.typeText(text)
        }
    }

    private func register(email: String, password: String = "secret123") {
        let agree = app.buttons["Agree & Continue"]
        XCTAssertTrue(agree.waitForExistence(timeout: 10), "welcome screen not shown")
        agree.tap()

        fill(app.textFields["Display Name"], with: "UI Tester")
        fill(app.textFields["Email"], with: email)
        fill(app.textFields["Phone Number"], with: "08012345678")
        fill(app.secureTextFields["Password"], with: password)
        fill(app.secureTextFields["Confirm Password"], with: password)

        app.staticTexts["Create Account"].tap()    // dismiss the keyboard
        app.buttons["Register"].tap()
    }

    private func openSettingsTab() {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "tab bar not shown after sign-up")
        settings.tap()
    }

    private func scrollTo(_ element: XCUIElement) {
        var attempts = 0
        while !element.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
    }

    // MARK: Flows

    func testRegistrationShowsAllTabs() {
        register(email: "ui-\(UUID().uuidString.prefix(6))@example.com")
        for tab in ["Chats", "Feed", "Contacts", "Settings"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 10), "missing tab \(tab)")
        }
    }

    func testLogoutReturnsToWelcome() {
        register(email: "ui-\(UUID().uuidString.prefix(6))@example.com")
        openSettingsTab()
        let logout = app.buttons["Logout"]
        scrollTo(logout)
        logout.tap()
        XCTAssertTrue(app.buttons["Agree & Continue"].waitForExistence(timeout: 10))
    }

    func testWrongPasswordShowsLoginError() {
        let agree = app.buttons["Agree & Continue"]
        XCTAssertTrue(agree.waitForExistence(timeout: 10))
        agree.tap()
        // "Already have an account?" is static text; the tappable part is the "Login" button next to it.
        app.buttons["Login"].firstMatch.tap()

        fill(app.textFields["Email"], with: "nobody@example.com")
        fill(app.secureTextFields["Password"], with: "wrong-password")
        app.staticTexts["Welcome Back"].tap()
        app.buttons["Login"].tap()

        let alert = app.alerts["Login Error"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Incorrect email or password."].exists)
    }

    func testDeleteAccountFlowReturnsToWelcome() {
        register(email: "ui-\(UUID().uuidString.prefix(6))@example.com", password: "secret123")
        openSettingsTab()

        let delete = app.buttons["Delete Account"]
        scrollTo(delete)
        delete.tap()

        // Confirmation dialog -> password prompt -> account removed
        let confirm = app.sheets.buttons["Delete Account"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let prompt = app.alerts["Confirm your password"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        for character in "secret123" { prompt.secureTextFields["Password"].typeText(String(character)) }
        prompt.buttons["Delete"].tap()

        XCTAssertTrue(app.buttons["Agree & Continue"].waitForExistence(timeout: 10))
    }

    func testBlockedUsersScreenShowsEmptyState() {
        register(email: "ui-\(UUID().uuidString.prefix(6))@example.com")
        openSettingsTab()
        let blocked = app.buttons["Blocked Users"]
        scrollTo(blocked)
        blocked.tap()
        XCTAssertTrue(app.staticTexts["No blocked users"].waitForExistence(timeout: 5))
    }
}

// MARK: - Screen tour

/// Walks the main screens on the signed-in mock backend and attaches a screenshot of each, for visual
/// review in the test report (xcresult). Also checks that each screen's key content is reachable.
final class ScreenTourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait   // orientation can leak between runs on a cloned simulator
        app = XCUIApplication()
        app.launchEnvironment["MBUITesting"] = "1"
        app.launchEnvironment["MBUITestingSignedIn"] = "1"
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow", "OK", "Don’t Allow", "Don't Allow", "Allow Full Access"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Any element whose label contains `text` (bubbles combine sender and text into one label).
    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "missing tab \(name)")
        button.tap()
    }

    func testTour() {
        // Chats: inbox, a conversation, conversation info, requests, new message
        tab("Chats")
        let adaRow = element(containing: "Hey! How are you?")
        XCTAssertTrue(adaRow.waitForExistence(timeout: 5))
        snapshot("01-inbox")
        adaRow.tap()
        XCTAssertTrue(app.buttons["Conversation info"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Hey! How are you?").waitForExistence(timeout: 5))
        snapshot("02-conversation")
        app.buttons["Conversation info"].tap()
        XCTAssertTrue(element(containing: "Mute notifications").waitForExistence(timeout: 5))
        snapshot("03-conversation-info")
        app.buttons["Done"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Requests (1)"].tap()
        let bolaRow = element(containing: "we met at the conference")
        XCTAssertTrue(bolaRow.waitForExistence(timeout: 5))
        bolaRow.tap()
        XCTAssertTrue(app.buttons["Accept"].waitForExistence(timeout: 5))
        snapshot("04-message-request")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["New message"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Chat"].waitForExistence(timeout: 5))
        // Scope to the sheet's list: the inbox behind it shows the same names.
        let picker = app.collectionViews.containing(.staticText, identifier: "@ada").firstMatch
        XCTAssertTrue(picker.staticTexts["Ada"].waitForExistence(timeout: 5))
        picker.staticTexts["Ada"].tap()
        picker.staticTexts["Bola"].tap()
        XCTAssertTrue(app.textFields["Group name (optional)"].waitForExistence(timeout: 5))
        snapshot("05-new-group")
        app.buttons["Cancel"].tap()

        // Feed, comments, activity, search, profile
        tab("Feed")
        XCTAssertTrue(element(containing: "Welcome to MyBuddy!").waitForExistence(timeout: 5))
        snapshot("06-feed")
        app.buttons["New post"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New post"].waitForExistence(timeout: 5))
        snapshot("07-composer")
        app.buttons["Cancel"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Activity'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        snapshot("08-activity")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ada'")).firstMatch.tap()
        XCTAssertTrue(element(containing: "Followers").waitForExistence(timeout: 5))
        snapshot("08b-profile")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Settings and the new account screens
        tab("Settings")
        XCTAssertTrue(element(containing: "Edit profile").waitForExistence(timeout: 5))
        snapshot("09-settings")
        element(containing: "Edit profile").tap()
        XCTAssertTrue(app.navigationBars["Edit profile"].waitForExistence(timeout: 5))
        snapshot("10-edit-profile")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Privacy"].tap()
        XCTAssertTrue(element(containing: "Read receipts").waitForExistence(timeout: 5))
        snapshot("11-privacy")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Notifications"].tap()
        XCTAssertTrue(element(containing: "Message requests").waitForExistence(timeout: 5))
        snapshot("12-notifications")

        // Contacts
        tab("Contacts")
        snapshot("13-contacts")
    }

    func testSignedOutScreens() {
        // Sign out to capture onboarding.
        tab("Settings")
        app.buttons["Logout"].tap()
        XCTAssertTrue(app.buttons["Agree & Continue"].waitForExistence(timeout: 10))
        snapshot("20-welcome")
        app.buttons["Agree & Continue"].tap()
        // The first tap can land while the sign-out transition is still animating.
        if !app.staticTexts["Create Account"].waitForExistence(timeout: 3) { app.buttons["Agree & Continue"].tap() }
        XCTAssertTrue(app.staticTexts["Create Account"].waitForExistence(timeout: 5))
        snapshot("21-register")
        app.buttons["Login"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Welcome Back"].waitForExistence(timeout: 5))
        snapshot("22-login")
    }
}
