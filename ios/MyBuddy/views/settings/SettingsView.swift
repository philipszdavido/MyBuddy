//
//  SettingsView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthViewModel

    @State private var confirmDelete = false
    @State private var askPassword = false
    @State private var deletePassword = ""
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var account: AccountProfile?

    @FetchRequest(sortDescriptors: [], animation: .default) private var userDatas: FetchedResults<UserData>

    private var accountRepository: AccountRepository? { AppContainer.shared.accountRepository }

    var body: some View {
        List {
            profileSection

            if let repository = accountRepository {
                Section {
                    NavigationLink { PrivacySettingsView(repository: repository) } label: {
                        SettingsRow(title: "Privacy", systemImage: "lock.fill", tint: .blue)
                    }
                    NavigationLink { NotificationSettingsView(repository: repository) } label: {
                        SettingsRow(title: "Notifications", systemImage: "bell.badge.fill", tint: .red)
                    }
                }
            }

            Section {
                NavigationLink { MediaListView() } label: {
                    SettingsRow(title: "Media", systemImage: "photo.on.rectangle", tint: .purple)
                }
                NavigationLink { ManageDataView() } label: {
                    SettingsRow(title: "Manage Data", systemImage: "internaldrive.fill", tint: .gray)
                }
                NavigationLink { BlockedUsersView() } label: {
                    SettingsRow(title: "Blocked Users", systemImage: "hand.raised.fill", tint: .orange)
                }
            }

            if LegalLinks.terms != nil || LegalLinks.privacyPolicy != nil || LegalLinks.support != nil {
                Section("About") {
                    if let terms = LegalLinks.terms { Link(destination: terms) { SettingsRow(title: "Terms of Service", systemImage: "doc.text.fill", tint: .gray) } }
                    if let privacy = LegalLinks.privacyPolicy { Link(destination: privacy) { SettingsRow(title: "Privacy Policy", systemImage: "hand.raised.square.fill", tint: .gray) } }
                    if let support = LegalLinks.support { Link(destination: support) { SettingsRow(title: "Help & Support", systemImage: "questionmark.circle.fill", tint: .gray) } }
                }
                .foregroundStyle(DS.Palette.primaryText)
            }

            Section {
                Button("Logout") { auth.logout() }
                    .foregroundStyle(DS.Palette.accent)
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    if isDeleting { ProgressView() } else { Text("Delete Account") }
                }
                .disabled(isDeleting)
            } footer: {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Permanently deletes your account. This cannot be undone.")
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text("MyBuddy \(version)").frame(maxWidth: .infinity).padding(.top, DS.Space.l)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .task(id: auth.accountID) { account = try? await accountRepository?.me() }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { askPassword = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile, posts and messages will be removed. This cannot be undone.")
        }
        .alert("Confirm your password", isPresented: $askPassword) {
            SecureField("Password", text: $deletePassword)
            Button("Delete", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) { deletePassword = "" }
        } message: {
            Text("Enter your password to permanently delete your account.")
        }
        .alert(
            "Couldn't delete account",
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(deleteError ?? "") }
        )
    }

    @ViewBuilder
    private var profileSection: some View {
        if let repository = accountRepository {
            Section {
                NavigationLink {
                    EditAccountView(repository: repository)
                        .onDisappear { Task { account = try? await repository.me() } }
                } label: {
                    ProfileHeaderRow(
                        user: UserSummary(id: account?.id ?? "", username: account?.username, displayName: account?.displayName ?? auth.userProfile?.displayName ?? "",
                                          avatarURL: account?.avatarURL, isVerified: false),
                        subtitle: account?.username.map { "@\($0)" } ?? auth.userProfile?.email ?? "",
                        detail: "Edit profile"
                    )
                }
            }
        } else {
            ForEach(userDatas) { user in
                if let contact = CoreDataUtils.shared.getContactWithNumber(phoneNumber: user.phoneNumber), let userId = user.id {
                    ContactSectionView(contact: contact, user: user, userId: userId)
                }
            }
        }
    }
}

extension SettingsView {
    func deleteAccount() {
        let password = deletePassword
        deletePassword = ""
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do { try await auth.deleteAccount(password: password) }
            catch { deleteError = AppError.wrap(error).userMessage }
        }
    }
}

/// Avatar, name and a secondary line at the top of Settings.
private struct ProfileHeaderRow: View {
    let user: UserSummary
    let subtitle: String
    let detail: String

    var body: some View {
        HStack(spacing: DS.Space.m) {
            AvatarView(user: user, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(.title3.weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(DS.Palette.secondaryText)
                Text(detail).font(.caption).foregroundStyle(DS.Palette.accent)
            }
        }
        .padding(.vertical, DS.Space.xxs)
    }
}

/// Firebase backend: profile row from the local store, editing via EditProfileView.
struct ContactSectionView: View {
    @ObservedObject var contact: Contact
    let user: UserData
    let userId: String

    var body: some View {
        Section {
            NavigationLink {
                EditProfileView(contact: contact, userId: userId)
            } label: {
                HStack(spacing: DS.Space.m) {
                    ProfilePhoto(contact: contact, width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName ?? "No name").font(.title3.weight(.semibold))
                        Text(String(user.phoneNumber)).font(.subheadline).foregroundStyle(DS.Palette.secondaryText)
                        Text(user.email ?? "").font(.caption).foregroundStyle(DS.Palette.secondaryText)
                    }
                }
                .padding(.vertical, DS.Space.xxs)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthViewModel.shared)
}
