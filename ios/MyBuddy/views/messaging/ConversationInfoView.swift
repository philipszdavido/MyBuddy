//
//  ConversationInfoView.swift
//  MyBuddy
//
//  Details of a conversation: group name and members (admins can rename, add and remove), mute,
//  and leave / delete.
//

import SwiftUI

struct ConversationInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var conversation: ChatConversation
    let meID: String
    let repository: MessagingRepository
    var onLeft: () -> Void

    @State private var title: String
    @State private var addingMembers = false
    @State private var confirmLeave = false
    @State private var working = false
    @State private var errorMessage: String?

    init(conversation: ChatConversation, meID: String, repository: MessagingRepository, onLeft: @escaping () -> Void) {
        _conversation = State(initialValue: conversation)
        _title = State(initialValue: conversation.title ?? "")
        self.meID = meID
        self.repository = repository
        self.onLeft = onLeft
    }

    private var isGroup: Bool { conversation.kind == .group }
    private var isAdmin: Bool { conversation.isAdmin(meID) }

    var body: some View {
        List {
            Section {
                VStack(spacing: DS.Space.s) {
                    ConversationAvatar(conversation: conversation, meID: meID, size: 84)
                    Text(conversation.displayName(me: meID)).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    if isGroup { Text("Group · \(conversation.participants.count) members").font(.subheadline).foregroundStyle(DS.Palette.secondaryText) }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            if isGroup && isAdmin {
                Section("Group name") {
                    TextField("Add a group name", text: $title)
                        .submitLabel(.done)
                        .onSubmit { Task { await rename() } }
                    if title != (conversation.title ?? "") {
                        Button("Save name") { Task { await rename() } }.disabled(working)
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { conversation.muted }, set: { muted in Task { await setMuted(muted) } })) {
                    SettingsRow(title: "Mute notifications", systemImage: "bell.slash.fill", tint: .gray)
                }
            }

            Section(isGroup ? "Members" : "") {
                if isGroup && isAdmin {
                    Button { addingMembers = true } label: { Label("Add members", systemImage: "person.badge.plus") }
                }
                ForEach(conversation.participants) { p in
                    HStack(spacing: DS.Space.s) {
                        AvatarView(user: p.user, size: 36)
                        VStack(alignment: .leading) {
                            Text(p.id == meID ? "You" : p.user.displayName)
                            if let u = p.user.username { Text("@\(u)").font(.caption).foregroundStyle(DS.Palette.secondaryText) }
                        }
                        Spacer()
                        if p.isAdmin { Text("Admin").font(.caption.weight(.medium)).foregroundStyle(DS.Palette.secondaryText) }
                    }
                    .swipeActions {
                        if isGroup && isAdmin && p.id != meID {
                            Button(role: .destructive) { Task { await remove(p) } } label: { Label("Remove", systemImage: "person.badge.minus") }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) { confirmLeave = true } label: {
                    Text(isGroup ? "Leave group" : "Delete conversation")
                }
            } footer: {
                Text(isGroup ? "You'll stop receiving messages from this group." : "Deletes the history on your devices only.")
            }
        }
        .navigationTitle(isGroup ? "Group info" : "Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .confirmationDialog(isGroup ? "Leave this group?" : "Delete this conversation?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(isGroup ? "Leave" : "Delete", role: .destructive) { Task { await leave() } }
        }
        .sheet(isPresented: $addingMembers) {
            AddMembersView(repository: repository, existing: Set(conversation.participants.map(\.id))) { ids in
                addingMembers = false
                Task { await add(ids) }
            }
        }
        .errorAlert($errorMessage)
    }

    private func run(_ op: () async throws -> Void) async {
        working = true
        defer { working = false }
        do { try await op() } catch { errorMessage = AppError.wrap(error).userMessage }
    }

    private func rename() async {
        await run { conversation = try await repository.rename(conversationID: conversation.id, title: title.trimmingCharacters(in: .whitespaces)) }
    }

    private func setMuted(_ muted: Bool) async {
        await run {
            try await repository.setMuted(conversationID: conversation.id, muted)
            conversation.muted = muted
        }
    }

    private func add(_ ids: [String]) async {
        await run { conversation = try await repository.addMembers(conversationID: conversation.id, userIDs: ids) }
    }

    private func remove(_ p: ChatParticipant) async {
        await run {
            try await repository.removeMember(conversationID: conversation.id, userID: p.id)
            conversation.participants.removeAll { $0.id == p.id }
        }
    }

    private func leave() async {
        await run {
            try await repository.leave(conversationID: conversation.id)
            dismiss()
            onLeft()
        }
    }
}

private struct AddMembersView: View {
    @Environment(\.dismiss) private var dismiss
    let repository: MessagingRepository
    let existing: Set<String>
    var onAdd: ([String]) -> Void
    @State private var contacts: [UserSummary] = []
    @State private var selected = Set<String>()

    var body: some View {
        NavigationStack {
            List(contacts.filter { !existing.contains($0.id) }) { user in
                Button {
                    if selected.contains(user.id) { selected.remove(user.id) } else { selected.insert(user.id) }
                } label: {
                    HStack(spacing: DS.Space.s) {
                        AvatarView(user: user, size: 36)
                        UserNameLabel(user: user)
                        Spacer()
                        Image(systemName: selected.contains(user.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(user.id) ? DS.Palette.accent : DS.Palette.tertiaryText)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay { if contacts.filter({ !existing.contains($0.id) }).isEmpty { ContentUnavailableView("Everyone's here", systemImage: "person.3") } }
            .navigationTitle("Add members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { onAdd(Array(selected)) }.disabled(selected.isEmpty) }
            }
            .task { contacts = (try? await repository.contacts()) ?? [] }
        }
    }
}
