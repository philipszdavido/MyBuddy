//
//  ChatRoomView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import SwiftUI
import CoreData

struct ChatRoomView: View {
    private let chatRoomViewModel = ChatRoomViewModel()
    private let coreDataUtils = CoreDataUtils()
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @FetchRequest private var messages: FetchedResults<Message>
    
    @State private var messageText: String = ""
    @State private var showSendButton: Bool = false
    @State private var confirmBlock = false
    @State private var chooseReportReason = false
    @State private var safetyNotice: String?
    
    var chatId: String
    var currentUserId: String
    var recipientUserId: String
    var currentUserPhoneNumber: Int64
    var recipientUserPhoneNumber: Int64
    var contact: Contact
    @StateObject private var keyboard = KeyboardResponder()

    var body: some View {

        VStack {
            
            VStack(spacing: 0) {
                
                // Header
                ChatRoomHeader(
                    currentUserPhoneNumber: currentUserPhoneNumber,
                    recipientUserPhoneNumber: recipientUserPhoneNumber,
                    contact: contact,
                    onReport: { chooseReportReason = true },
                    onBlock: { confirmBlock = true }
                )
                .frame(maxWidth: .infinity)
                
                // Chat ScrollView
                ChatListScroll(
                    chatId: chatId,
                    currentUserId: currentUserId,
                    recipientUserId: recipientUserId,
                    messages: Array(messages),
                    onReachTop: {
                        Task { await ChatSyncService.shared.loadOlderMessages(chatID: chatId) }
                    }
                )
                
                Spacer()
                
                // Bottom Input Bar
                ChatInputBar(
                    text: $messageText,
                    colorScheme: colorScheme,
                    onSend: { onSend(messageText: messageText) },
                    onImageSend: onMediaSend
                )
            }
            
        }
        .background(
            Image("bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
        .hideKeyboardOnTap()
        .navigationBarBackButtonHidden(true)
        .onAppear { AppContainer.shared.deepLinkRouter.activeChatID = chatId }
        .onDisappear {
            let router = AppContainer.shared.deepLinkRouter
            if router.activeChatID == chatId { router.activeChatID = nil }
        }
        .confirmationDialog("Block this user?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { blockRecipient() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to message you, and this chat will be hidden. You can unblock them in Settings.")
        }
        .confirmationDialog("Report this user", isPresented: $chooseReportReason, titleVisibility: .visible) {
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button(reason.title) { reportRecipient(reason) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "MyBuddy",
            isPresented: Binding(get: { safetyNotice != nil }, set: { if !$0 { safetyNotice = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(safetyNotice ?? "") }
        )
        .task(id: chatId) {
            // Bounded listener; cancelled automatically when the view disappears.
            await ChatSyncService.shared.syncMessages(chatID: chatId)
        }
    }
    
    private func blockRecipient() {
        let user = BlockedUser(
            id: recipientUserId,
            phoneNumber: recipientUserPhoneNumber,
            displayName: contact.displayName ?? String(recipientUserPhoneNumber),
            blockedAt: Date()
        )
        Task {
            do {
                try await BlockedUsersStore.shared.block(user)
                dismiss()
            } catch {
                safetyNotice = AppError.wrap(error).userMessage
            }
        }
    }

    private func reportRecipient(_ reason: ReportReason) {
        Task {
            do {
                try await BlockedUsersStore.shared.report(userID: recipientUserId, reason: reason, conversationID: chatId)
                safetyNotice = String(localized: "report.sent", defaultValue: "Thanks. Your report was sent to our moderators.")
            } catch {
                safetyNotice = AppError.wrap(error).userMessage
            }
        }
    }

    var log: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("chatId: \(chatId)")
            Text("currentUserId: \(currentUserId)")
            Text("recipientUserId: \(recipientUserId)")
            Text("currentUserPhoneNumber: \(currentUserPhoneNumber)")
            Text("recipientUserPhoneNumber: \(recipientUserPhoneNumber)")
        }
        .font(.caption)
        .foregroundColor(.gray)
    }

    init(
        chatId: String,
        currentUserId: String,
        recipientUserId: String,
        currentUserPhoneNumber: Int64,
        recipientUserPhoneNumber: Int64,
        contact: Contact
    ) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.recipientUserId = recipientUserId
        self.currentUserPhoneNumber = currentUserPhoneNumber
        self.recipientUserPhoneNumber = recipientUserPhoneNumber
        self.contact = contact
        
        let predicate = NSPredicate(format: "chatId == %@", chatId)
        _messages = FetchRequest<Message>(
            entity: Message.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Message.timestamp, ascending: true)],
            predicate: predicate
        )
        
    }
    
    func onSend(messageText: String) {
        
        withAnimation {
            
            DispatchQueue.main.async {
                
                chatRoomViewModel
                    .sendMessage(
                        chatId: chatId,
                        currentUserId: currentUserId,
                        recipientUserId: recipientUserId,
                        messageText: messageText,
                        recipientUserPhoneNumber: recipientUserPhoneNumber,
                        currentUserPhoneNumber: currentUserPhoneNumber
                    )
                
            }
            
        }

    }
    
    func onMediaSend(_ selectedImage: UIImage?, _ text: String) {
        guard let selectedImage else { return }
        // Stored locally first (visible immediately as "sending"); upload + send are retried by the outbox.
        chatRoomViewModel.sendImage(
            selectedImage,
            caption: text,
            chatId: chatId,
            currentUserId: currentUserId,
            recipientUserId: recipientUserId,
            recipientUserPhoneNumber: recipientUserPhoneNumber,
            currentUserPhoneNumber: currentUserPhoneNumber
        )
    }

}

struct ChatRoomView_Preview: View {
    var body: some View {
        let contact = Contact(context:  PersistenceController.preview.container.viewContext)
        contact.phoneNumber = 998765
        contact.id = UUID().uuidString
        contact.timestamp = .now

        return NavigationStack {
            ChatRoomView(
                chatId: "nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection",
                currentUserId: "nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection",
                recipientUserId: "nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection",
                currentUserPhoneNumber: 12323443,
                recipientUserPhoneNumber: 08978675,
                contact: contact
            )
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
}

#Preview {
    
    ChatRoomView_Preview()
}

extension ReportReason {
    var title: String {
        switch self {
        case .spam: return String(localized: "report.spam", defaultValue: "Spam")
        case .harassment: return String(localized: "report.harassment", defaultValue: "Harassment or bullying")
        case .inappropriate: return String(localized: "report.inappropriate", defaultValue: "Inappropriate content")
        case .impersonation: return String(localized: "report.impersonation", defaultValue: "Pretending to be someone else")
        case .other: return String(localized: "report.other", defaultValue: "Something else")
        }
    }
}
