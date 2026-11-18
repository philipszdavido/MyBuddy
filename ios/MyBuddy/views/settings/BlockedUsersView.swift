//
//  BlockedUsersView.swift
//  MyBuddy
//

import SwiftUI

struct BlockedUsersView: View {
    @ObservedObject private var store = BlockedUsersStore.shared
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(store.blocked) { user in
                HStack {
                    Text(user.displayName.isEmpty ? String(user.phoneNumber) : user.displayName)
                    Spacer()
                    Button("Unblock") { unblock(user) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Unblock \(user.displayName)")
                }
                .swipeActions {
                    Button("Unblock") { unblock(user) }.tint(.blue)
                }
            }
        }
        .overlay {
            if store.blocked.isEmpty {
                ContentUnavailableView(
                    "No blocked users",
                    systemImage: "hand.raised",
                    description: Text("People you block can't message you and won't appear in your chats or feed.")
                )
            }
        }
        .navigationTitle("Blocked Users")
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private func unblock(_ user: BlockedUser) {
        Task {
            do { try await store.unblock(userID: user.id) }
            catch { errorMessage = AppError.wrap(error).userMessage }
        }
    }
}
