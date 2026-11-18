//
//  ContactsList.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 14/07/2025.
//

import SwiftUI
import CoreData

struct ContactsList: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [SortDescriptor(\.displayName)], animation: .default)
    private var contacts: FetchedResults<Contact>

    @FetchRequest(sortDescriptors: [], animation: .default)
    private var userData: FetchedResults<UserData>

    private let coreDataUtils = CoreDataUtils.shared
    @State private var query = ""

    private var visible: [Contact] {
        let me = userData.first?.phoneNumber
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return contacts.filter { $0.phoneNumber != me && (q.isEmpty || ($0.displayName ?? "").lowercased().contains(q) || String($0.phoneNumber).contains(q)) }
    }

    var body: some View {
        List {
            ForEach(visible) { contact in
                NavigationLink {
                    if let currentUserPhoneNumber = userData.first?.phoneNumber, let currentUserId = userData.first?.id {
                        ResolvedChatRoom(
                            currentUserId: currentUserId,
                            recipientUserId: contact.id ?? "",
                            currentUserPhoneNumber: currentUserPhoneNumber,
                            recipientUserPhoneNumber: contact.phoneNumber,
                            contact: contact
                        ).toolbar(.hidden, for: ToolbarPlacement.tabBar)
                    }
                } label: {
                    HStack(spacing: DS.Space.s) {
                        ProfilePhoto(contact: contact, width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.displayName ?? "").font(.body)
                            Text("+\(String(contact.phoneNumber))").font(.subheadline).foregroundStyle(DS.Palette.secondaryText)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { indexSet in
                withAnimation {
                    for index in indexSet {
#if DEBUG
                        viewContext.delete(visible[index])
#else
                        coreDataUtils.deleteContact(object: visible[index])
#endif
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if visible.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("No contacts on MyBuddy yet", systemImage: "person.2",
                                           description: Text("Contacts from your address book who use MyBuddy appear here."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .searchable(text: $query, prompt: "Search contacts")
        .navigationTitle("Contacts")
    }
}

/// Asks the chat backend for the one-to-one conversation id (computed locally on Firebase, created on
/// the MyBuddy API), then shows the unchanged ChatRoomView.
private struct ResolvedChatRoom: View {
    let currentUserId: String
    let recipientUserId: String
    let currentUserPhoneNumber: Int64
    let recipientUserPhoneNumber: Int64
    let contact: Contact

    @State private var chatId: String?
    @State private var failed = false

    var body: some View {
        Group {
            if let messaging = AppContainer.shared.messagingRepository, let chatId {
                ConversationView(conversationID: chatId, repository: messaging, social: AppContainer.shared.socialRepository)
            } else if let chatId {
                ChatRoomView(
                    chatId: chatId,
                    currentUserId: currentUserId,
                    recipientUserId: recipientUserId,
                    currentUserPhoneNumber: currentUserPhoneNumber,
                    recipientUserPhoneNumber: recipientUserPhoneNumber,
                    contact: contact
                )
            } else if failed {
                ContentUnavailableView {
                    Label("Couldn't open chat", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(AppError.network(underlying: "").userMessage)
                } actions: {
                    Button("Try again") { Task { await resolve() } }
                }
            } else {
                ProgressView()
            }
        }
        .task { await resolve() }
    }

    private func resolve() async {
        failed = false
        do {
            chatId = try await AppContainer.shared.chatRepository.conversationID(
                currentUserID: currentUserId, currentPhone: currentUserPhoneNumber,
                recipientID: recipientUserId, recipientPhone: recipientUserPhoneNumber
            )
        } catch {
            Log.chat.error("conversation lookup failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
            failed = true
        }
    }
}

#Preview {
    
    NavigationStack {
        ContactsList()
    }
    .environment(
        \.managedObjectContext,
         PersistenceController.preview.container.viewContext
    )
        .environmentObject(AuthViewModel.shared)
}
