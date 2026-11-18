//
//  InboxView.swift
//  MyBuddy
//
//  Chats tab on the MyBuddy API backend: conversations (direct and group) and message requests.
//

import SwiftUI

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var conversations: [ChatConversation] = []
    @Published private(set) var requests: [ChatConversation] = []
    @Published private(set) var contacts: [UserSummary] = []
    @Published private(set) var loaded = false
    @Published private(set) var meID = ""
    @Published var query = ""
    @Published var errorMessage: String?
    let repository: MessagingRepository
    private var eventsTask: Task<Void, Never>?

    init(repository: MessagingRepository) { self.repository = repository }

    var filtered: [ChatConversation] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return conversations }
        return conversations.filter { c in
            c.displayName(me: meID).lowercased().contains(q) || (c.lastMessage?.text ?? "").lowercased().contains(q)
        }
    }

    func start() async {
        meID = (try? await repository.currentUserID()) ?? ""
        async let people = try? repository.contacts()
        await reload()
        contacts = await people ?? []
        eventsTask?.cancel()
        let stream = repository.events()
        eventsTask = Task { [weak self] in
            for await event in stream {
                switch event {
                case .connected, .message, .conversationChanged, .messageDeleted: await self?.reload(quiet: true)
                default: break
                }
            }
        }
    }

    func stop() { eventsTask?.cancel() }

    func reload(quiet: Bool = false) async {
        do {
            async let chats = repository.conversations(requests: false, cursor: nil)
            async let pending = repository.conversations(requests: true, cursor: nil)
            let (c, r) = try await (chats, pending)
            withAnimation(.snappy) {
                conversations = c.items
                requests = r.items
            }
        } catch {
            if !quiet { errorMessage = AppError.wrap(error).userMessage }
        }
        loaded = true
    }

    func leave(_ c: ChatConversation) async {
        withAnimation { conversations.removeAll { $0.id == c.id }; requests.removeAll { $0.id == c.id } }
        do { try await repository.leave(conversationID: c.id) } catch { errorMessage = AppError.wrap(error).userMessage; await reload() }
    }

    func toggleMute(_ c: ChatConversation) async {
        Haptics.selection()
        do {
            try await repository.setMuted(conversationID: c.id, !c.muted)
            if let i = conversations.firstIndex(where: { $0.id == c.id }) { conversations[i].muted.toggle() }
        } catch { errorMessage = AppError.wrap(error).userMessage }
    }

    /// One tap from the people row: reuse or create the direct chat.
    func chat(with user: UserSummary) async -> String? {
        do { return try await repository.startConversation(with: [user.id], title: nil).id }
        catch { errorMessage = AppError.wrap(error).userMessage; return nil }
    }
}

enum InboxRoute: Hashable {
    case conversation(String)
    case requests
}

struct InboxView: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @StateObject private var model: InboxViewModel
    private let social: SocialRepository?
    @State private var path = NavigationPath()
    @State private var composing = false

    init(repository: MessagingRepository, social: SocialRepository?) {
        self.social = social
        _model = StateObject(wrappedValue: InboxViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !model.contacts.isEmpty && model.query.isEmpty {
                    peopleRow
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }

                if !model.requests.isEmpty && model.query.isEmpty {
                    NavigationLink(value: InboxRoute.requests) {
                        HStack(spacing: DS.Space.s) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 54, height: 54)
                                .background(DS.Brand.gradient, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Message requests").font(.body.weight(.semibold))
                                Text(requestSubtitle).font(.subheadline).foregroundStyle(DS.Palette.secondaryText).lineLimit(1)
                            }
                            Spacer()
                            CountBadge(count: model.requests.count)
                        }
                        .padding(.vertical, DS.Space.xxs)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Requests (\(model.requests.count))")
                    .accessibilityAddTraits(.isButton)
                }

                if !model.loaded {
                    SkeletonList(rows: 7)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }

                ForEach(model.filtered) { c in
                    NavigationLink(value: InboxRoute.conversation(c.id)) {
                        ConversationRow(conversation: c, meID: model.meID)
                    }
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await model.leave(c) } } label: {
                            Label(c.kind == .group ? "Leave" : "Delete", systemImage: c.kind == .group ? "rectangle.portrait.and.arrow.right" : "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { Task { await model.toggleMute(c) } } label: {
                            Label(c.muted ? "Unmute" : "Mute", systemImage: c.muted ? "bell.fill" : "bell.slash.fill")
                        }
                        .tint(.indigo)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.Palette.background)
            .overlay {
                if model.loaded && model.filtered.isEmpty && model.requests.isEmpty {
                    if model.query.isEmpty {
                        BrandEmptyState(systemImage: "bubble.left.and.bubble.right.fill", title: "No conversations yet",
                                        message: "Message a contact or start a group. Everything stays in sync across your devices.",
                                        actionTitle: "New message") { composing = true }
                    } else {
                        ContentUnavailableView.search(text: model.query)
                    }
                }
            }
            .searchable(text: $model.query, prompt: "Search")
            .refreshable { await model.reload() }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptics.tap(); composing = true } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(DS.Brand.gradient, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("New message")
                }
            }
            .navigationDestination(for: InboxRoute.self) { route in
                switch route {
                case .conversation(let id):
                    ConversationView(conversationID: id, repository: model.repository, social: social)
                case .requests:
                    RequestsView(model: model) { path.append(InboxRoute.conversation($0)) }
                }
            }
            .sheet(isPresented: $composing) {
                NewConversationView(repository: model.repository) { conversation in
                    composing = false
                    path.append(InboxRoute.conversation(conversation.id))
                }
            }
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: router.pending) { openPendingChat() }
        .onAppear { openPendingChat() }
        .errorAlert($model.errorMessage)
    }

    private var requestSubtitle: String {
        let names = model.requests.prefix(2).map { $0.displayName(me: model.meID) }
        return model.requests.count > 2 ? "\(names.joined(separator: ", ")) and \(model.requests.count - 2) more" : names.joined(separator: ", ")
    }

    /// People you can message, one tap away.
    private var peopleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.m) {
                ForEach(model.contacts) { user in
                    Button {
                        Haptics.tap()
                        Task { if let id = await model.chat(with: user) { path.append(InboxRoute.conversation(id)) } }
                    } label: {
                        VStack(spacing: 6) {
                            AvatarView(user: user, size: 58, ring: hasUnread(from: user))
                            Text(user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.primaryText)
                                .lineLimit(1)
                        }
                        .frame(width: 66)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Message \(user.displayName)")
                }
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
        }
    }

    private func hasUnread(from user: UserSummary) -> Bool {
        model.conversations.contains { $0.kind == .direct && $0.unreadCount > 0 && $0.others(model.meID).first?.id == user.id }
    }

    /// Notification tap / deep link to a chat.
    private func openPendingChat() {
        guard case .chat(let id)? = router.pending else { return }
        _ = router.consume()
        path = NavigationPath([InboxRoute.conversation(id)])
    }
}

/// Requests from people you're not connected to.
private struct RequestsView: View {
    @ObservedObject var model: InboxViewModel
    var open: (String) -> Void

    var body: some View {
        List {
            Section {
                ForEach(model.requests) { c in
                    Button { open(c.id) } label: { ConversationRow(conversation: c, meID: model.meID) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) { Task { await model.leave(c) } } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            } footer: {
                Text("Messages from people you're not connected to. They won't know you've seen them until you accept.")
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.requests.isEmpty {
                BrandEmptyState(systemImage: "tray.fill", title: "No requests", message: "Requests from people you don't know appear here.")
            }
        }
        .navigationTitle("Message requests")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConversationRow: View {
    let conversation: ChatConversation
    let meID: String

    private var unread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        HStack(spacing: DS.Space.s) {
            ConversationAvatar(conversation: conversation, meID: meID, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xxs) {
                    Text(conversation.displayName(me: meID))
                        .font(.body.weight(unread ? .bold : .semibold))
                        .lineLimit(1)
                    if conversation.muted {
                        Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(DS.Palette.tertiaryText)
                            .accessibilityLabel("Muted")
                    }
                    Spacer(minLength: DS.Space.xs)
                    Text(conversation.lastActivity.listTimestamp)
                        .font(.caption.weight(unread ? .semibold : .regular))
                        .foregroundStyle(unread ? DS.Palette.accent : DS.Palette.secondaryText)
                }
                HStack(alignment: .center, spacing: DS.Space.xxs) {
                    if let tick = tick {
                        Image(systemName: tick.symbol).font(.caption.weight(.semibold)).foregroundStyle(tick.color)
                            .accessibilityLabel(tick.label)
                    }
                    Text(preview)
                        .font(.subheadline.weight(unread ? .medium : .regular))
                        .foregroundStyle(unread ? DS.Palette.primaryText : DS.Palette.secondaryText)
                        .lineLimit(2)
                    Spacer(minLength: DS.Space.xs)
                    CountBadge(count: conversation.unreadCount)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// Delivery state of my own last message: sent, or seen by everyone else.
    private var tick: (symbol: String, color: Color, label: String)? {
        guard let m = conversation.lastMessage, m.senderID == meID, !m.deleted else { return nil }
        let others = conversation.others(meID)
        let seen = !others.isEmpty && others.allSatisfy { ($0.lastReadSeq ?? 0) >= m.seq }
        return seen ? ("checkmark.circle.fill", DS.Palette.accent, "Seen") : ("checkmark", DS.Palette.tertiaryText, "Sent")
    }

    private var preview: String {
        guard let m = conversation.lastMessage else { return conversation.kind == .group ? "Group created" : "Say hello 👋" }
        if m.deleted { return "Message deleted" }
        let body = m.text?.isEmpty == false ? m.text! : (m.kind == .video ? "🎥 Video" : m.kind == .image ? "📷 Photo" : "")
        if m.senderID == meID { return body }
        if conversation.kind == .group, let name = m.sender?.displayName.split(separator: " ").first { return "\(name): \(body)" }
        return body
    }
}

/// Single avatar for direct chats, overlapping pair for groups.
struct ConversationAvatar: View {
    let conversation: ChatConversation
    let meID: String
    var size: CGFloat = 50

    var body: some View {
        let others = conversation.others(meID)
        if conversation.kind == .group && others.count > 1 {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(user: others[0].user, size: size * 0.72).offset(x: -size * 0.14, y: -size * 0.14)
                AvatarView(user: others[1].user, size: size * 0.72)
                    .overlay(Circle().stroke(DS.Palette.background, lineWidth: 2))
                    .offset(x: size * 0.14, y: size * 0.14)
            }
            .frame(width: size, height: size)
        } else {
            AvatarView(user: others.first?.user, size: size)
        }
    }
}

// MARK: - New conversation

struct NewConversationView: View {
    @Environment(\.dismiss) private var dismiss
    let repository: MessagingRepository
    var onCreated: (ChatConversation) -> Void

    @State private var contacts: [UserSummary] = []
    @State private var selected: [UserSummary] = []
    @State private var query = ""
    @State private var groupName = ""
    @State private var loading = true
    @State private var creating = false
    @State private var errorMessage: String?

    private var filtered: [UserSummary] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return contacts }
        return contacts.filter { $0.displayName.lowercased().contains(q) || ($0.username ?? "").contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if selected.count > 1 {
                    Section {
                        TextField("Group name (optional)", text: $groupName)
                    } footer: {
                        Text("\(selected.count + 1) people, including you. You'll be the group admin.")
                    }
                }
                if !selected.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Space.s) {
                                ForEach(selected) { user in
                                    Button { toggle(user) } label: {
                                        VStack(spacing: DS.Space.xxs) {
                                            AvatarView(user: user, size: 44).overlay(alignment: .topTrailing) {
                                                Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Palette.secondaryText).background(Circle().fill(DS.Palette.background))
                                            }
                                            Text(user.displayName.split(separator: " ").first.map(String.init) ?? "").font(.caption2).lineLimit(1)
                                        }
                                        .frame(width: 56)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(user.displayName)")
                                }
                            }
                        }
                    }
                }
                Section(contacts.isEmpty ? "" : "Contacts") {
                    if loading { ProgressView() }
                    if !loading && contacts.isEmpty {
                        Text("None of your contacts are on MyBuddy yet.").foregroundStyle(DS.Palette.secondaryText)
                    }
                    ForEach(filtered) { user in
                        Button { toggle(user) } label: {
                            HStack(spacing: DS.Space.s) {
                                AvatarView(user: user, size: 40)
                                VStack(alignment: .leading) {
                                    UserNameLabel(user: user)
                                    if let u = user.username { Text("@\(u)").font(.caption).foregroundStyle(DS.Palette.secondaryText) }
                                }
                                Spacer()
                                Image(systemName: selected.contains(user) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(user) ? DS.Palette.accent : DS.Palette.tertiaryText)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(user) ? .isSelected : [])
                    }
                }
            }
            .searchable(text: $query, prompt: "Search contacts")
            .navigationTitle(selected.count > 1 ? "New group" : "New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if creating { ProgressView() } else {
                        Button(selected.count > 1 ? "Create" : "Chat") { Task { await create() } }
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .task {
                contacts = (try? await repository.contacts()) ?? []
                loading = false
            }
            .errorAlert($errorMessage)
        }
    }

    private func toggle(_ user: UserSummary) {
        if let i = selected.firstIndex(of: user) { selected.remove(at: i) } else { selected.append(user) }
    }

    private func create() async {
        creating = true
        defer { creating = false }
        do {
            let name = groupName.trimmingCharacters(in: .whitespaces)
            let c = try await repository.startConversation(with: selected.map(\.id), title: selected.count > 1 && !name.isEmpty ? name : nil)
            onCreated(c)
        } catch {
            errorMessage = AppError.wrap(error).userMessage
        }
    }
}

#Preview {
    InboxView(repository: MockMessagingRepository(), social: MockSocialRepository())
        .environmentObject(DeepLinkRouter())
}
