//
//  PrivacyAndNotificationSettingsView.swift
//  MyBuddy
//
//  Privacy controls and per-type notification preferences (MyBuddy API backend). Changes save
//  immediately and roll back if the server rejects them.
//

import SwiftUI

struct PrivacySettingsView: View {
    let repository: AccountRepository
    @State private var settings: PrivacySettings?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let settings {
                Section {
                    Picker("Who can message you", selection: binding(\.allowMessagesFrom, current: settings)) {
                        ForEach(MessagePermission.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("With \"Everyone\", messages from people you're not connected to arrive as requests.")
                }

                Section {
                    Toggle("Show activity status", isOn: binding(\.showActivityStatus, current: settings))
                    Toggle("Read receipts", isOn: binding(\.sendReadReceipts, current: settings))
                } footer: {
                    Text("When off, others can't see when you're online or when you've read their messages.")
                }

                Section {
                    Toggle("Suggest my account to others", isOn: binding(\.discoverable, current: settings))
                } footer: {
                    Text("Controls whether you appear in search and suggestions. Your contacts can still find you.")
                }

                Section {
                    NavigationLink { BlockedUsersView() } label: { SettingsRow(title: "Blocked Users", systemImage: "hand.raised.fill", tint: .red) }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { settings = try await repository.me().settings } catch { errorMessage = AppError.wrap(error).userMessage }
        }
        .errorAlert($errorMessage)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<PrivacySettings, T>, current: PrivacySettings) -> Binding<T> {
        Binding(
            get: { (settings ?? current)[keyPath: keyPath] },
            set: { newValue in
                guard var next = settings else { return }
                let previous = next
                next[keyPath: keyPath] = newValue
                settings = next
                Task {
                    do { settings = try await repository.updatePrivacy(next).settings }
                    catch { settings = previous; errorMessage = AppError.wrap(error).userMessage }
                }
            }
        )
    }
}

struct NotificationSettingsView: View {
    let repository: AccountRepository
    @State private var preferences: [NotificationPreference] = []
    @State private var loading = true
    @State private var errorMessage: String?

    private let groups: [(String, [ActivityType])] = [
        ("Messages", [.message, .messageRequest]),
        ("Your network", [.follow, .followRequest, .followAccepted]),
        ("Your posts", [.postReaction, .comment, .commentReply, .commentReaction, .mention, .repost]),
    ]

    var body: some View {
        Form {
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        SettingsRow(title: "System notification settings", systemImage: "gear", tint: .gray)
                    }
                } footer: {
                    Text("Sounds, banners and the lock screen are controlled in iOS Settings.")
                }
                ForEach(groups, id: \.0) { title, types in
                    Section(title) {
                        ForEach(types, id: \.rawValue) { type in
                            if let index = preferences.firstIndex(where: { $0.type == type }) {
                                Toggle(type.settingsTitle, isOn: toggle(index, \.push))
                            }
                        }
                    }
                }
                Section {
                    ForEach(preferences.indices, id: \.self) { index in
                        if preferences[index].type != .message {
                            Toggle(preferences[index].type.settingsTitle, isOn: toggle(index, \.inApp))
                        }
                    }
                } header: {
                    Text("Show in Activity")
                } footer: {
                    Text("Turn a type off to keep it out of your activity inbox. Push notifications follow the switches above.")
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { preferences = try await repository.notificationPreferences() } catch { errorMessage = AppError.wrap(error).userMessage }
            loading = false
        }
        .errorAlert($errorMessage)
    }

    private func toggle(_ index: Int, _ keyPath: WritableKeyPath<NotificationPreference, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferences.indices.contains(index) ? preferences[index][keyPath: keyPath] : false },
            set: { value in
                let previous = preferences[index]
                preferences[index][keyPath: keyPath] = value
                let updated = preferences[index]
                Task {
                    do { try await repository.setNotificationPreference(updated) }
                    catch {
                        if let i = preferences.firstIndex(where: { $0.type == previous.type }) { preferences[i] = previous }
                        errorMessage = AppError.wrap(error).userMessage
                    }
                }
            }
        )
    }
}

#Preview("Privacy") { NavigationStack { PrivacySettingsView(repository: MockAccountRepository()) } }
#Preview("Notifications") { NavigationStack { NotificationSettingsView(repository: MockAccountRepository()) } }
