//
//  ConversationView.swift
//  MyBuddy
//
//  One conversation (direct or group) on the MyBuddy API backend.
//

import PhotosUI
import SwiftUI

struct ConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: DeepLinkRouter
    @StateObject private var model: ConversationViewModel
    private let repository: MessagingRepository
    private let social: SocialRepository?

    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showInfo = false
    @State private var atBottom = true
    @FocusState private var composerFocused: Bool

    init(conversationID: String, repository: MessagingRepository, social: SocialRepository?) {
        self.repository = repository
        self.social = social
        _model = StateObject(wrappedValue: ConversationViewModel(conversationID: conversationID, repository: repository, social: social))
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            if model.isRequest { requestBanner } else { composer }
        }
        .background(DS.Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel(model.isGroup ? "Group info" : "Conversation info")
                    .disabled(model.conversation == nil)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showInfo, onDismiss: { Task { await model.reloadConversation() } }) {
            if let conversation = model.conversation {
                NavigationStack {
                    ConversationInfoView(conversation: conversation, meID: model.meID, repository: repository, onLeft: { dismiss() })
                }
            }
        }
        .task { await model.start() }
        .onAppear { router.activeChatID = model.conversationID }
        .onDisappear {
            model.stop()
            if router.activeChatID == model.conversationID { router.activeChatID = nil }
        }
        .onChange(of: photoItem) { Task { await attachPhoto() } }
        .errorAlert($model.errorMessage)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.xs) {
            if let c = model.conversation { ConversationAvatar(conversation: c, meID: model.meID, size: 32) }
            VStack(alignment: .leading, spacing: 0) {
                Text(model.conversation?.displayName(me: model.meID) ?? " ")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Group {
                    if !model.typingUsers.isEmpty {
                        Text(typingText).foregroundStyle(DS.Palette.accent)
                    } else if let c = model.conversation, c.kind == .group {
                        Text("\(c.participants.count) members").foregroundStyle(DS.Palette.secondaryText)
                    }
                }
                .font(.caption2)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.typingUsers)
        .accessibilityElement(children: .combine)
    }

    private var typingText: String {
        let names = model.conversation?.participants.filter { model.typingUsers.contains($0.id) }.map(\.user.displayName) ?? []
        if model.isGroup, let first = names.first { return names.count > 1 ? "Several people are typing…" : "\(first) is typing…" }
        return "typing…"
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if model.hasOlder {
                        ProgressView().padding().task { await model.loadOlder() }
                    }
                    if model.loading {
                        ProgressView().padding(.top, 60)
                    } else if model.items.isEmpty {
                        BrandEmptyState(systemImage: "hand.wave.fill", title: "Say hello",
                                        message: "Messages arrive instantly and stay in sync on all your devices.")
                            .padding(.top, 80)
                    }
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        let previous = index > 0 ? model.items[index - 1] : nil
                        let next = index + 1 < model.items.count ? model.items[index + 1] : nil
                        let newDay = previous == nil || !Calendar.current.isDate(previous!.message.createdAt, inSameDayAs: item.message.createdAt)
                        let joinsPrevious = !newDay && previous?.message.senderID == item.message.senderID
                        let joinsNext = next.map { $0.message.senderID == item.message.senderID && Calendar.current.isDate($0.message.createdAt, inSameDayAs: item.message.createdAt) } ?? false
                        if newDay { DaySeparator(date: item.message.createdAt) }
                        MessageRow(
                            item: item,
                            isMine: item.message.senderID == model.meID,
                            showSender: model.isGroup && item.message.senderID != model.meID && !joinsPrevious,
                            joinsPrevious: joinsPrevious,
                            isLastInGroup: !joinsNext,
                            seen: item.state == .sent && item.message.senderID == model.meID && next == nil && (model.seenSeq ?? 0) >= item.message.seq,
                            onRetry: { model.retry(item) },
                            onDiscard: { model.discard(item) },
                            onDelete: { Task { await model.delete(item) } }
                        )
                        .id(item.id)
                    }
                    if !model.typingUsers.isEmpty { TypingBubble().id("typing").transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomLeading))) }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xs)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.items.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.items.last?.id) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom && !model.items.isEmpty {
                    Button {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.Palette.primaryText)
                            .frame(width: 40, height: 40)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    }
                    .buttonStyle(.pressable)
                    .padding(DS.Space.m)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Jump to latest")
                }
            }
            .animation(.snappy, value: atBottom)
        }
    }

    // MARK: Composer

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: DS.Space.xs) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: 38, height: 38)
                    .background(DS.Palette.accent.opacity(0.12), in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Send a photo")

            HStack(alignment: .bottom) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .onChange(of: draft) { model.userIsTyping(draft) }
                    .padding(.vertical, 9)
                if canSend {
                    Button {
                        Haptics.soft()
                        model.send(text: draft)
                        draft = ""
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(DS.Brand.gradient, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .padding(.bottom, 4)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Send")
                }
            }
            .padding(.leading, DS.Space.s)
            .padding(.trailing, canSend ? 4 : DS.Space.s)
            .background(DS.Palette.fieldBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: canSend)
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs)
        .background(.bar)
    }

    private var requestBanner: some View {
        VStack(spacing: DS.Space.s) {
            Text("\(model.conversation?.displayName(me: model.meID) ?? "Someone") wants to send you a message")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("They won't know you've seen it until you accept.")
                .font(.caption)
                .foregroundStyle(DS.Palette.secondaryText)
            HStack(spacing: DS.Space.s) {
                Button("Delete", role: .destructive) {
                    Task { if await model.declineRequest() { dismiss() } }
                }
                .buttonStyle(.secondary)
                Button("Accept") { Task { await model.acceptRequest() } }
                    .buttonStyle(.primary)
            }
        }
        .padding(DS.Space.m)
        .background(.bar)
    }

    private func attachPhoto() async {
        guard let item = photoItem else { return }
        photoItem = nil
        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            model.send(image: image, caption: draft)
            draft = ""
        }
    }
}

// MARK: - Rows

private struct MessageRow: View {
    let item: TranscriptItem
    let isMine: Bool
    let showSender: Bool
    let joinsPrevious: Bool
    let isLastInGroup: Bool
    let seen: Bool
    var onRetry: () -> Void
    var onDiscard: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
            if showSender, let sender = item.message.sender {
                Text(sender.displayName).font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.secondaryText)
                    .padding(.leading, 40)
                    .padding(.top, DS.Space.xs)
            }
            HStack(alignment: .bottom, spacing: DS.Space.xs) {
                if isMine { Spacer(minLength: 48) }
                if !isMine {
                    if isLastInGroup { AvatarView(user: item.message.sender, size: 28) } else { Color.clear.frame(width: 28, height: 28) }
                }
                bubble
                if !isMine { Spacer(minLength: 48) }
            }
            footer
        }
        .padding(.top, joinsPrevious ? 0 : 3)
        .padding(.bottom, isLastInGroup ? DS.Space.xs : 0)
    }

    @ViewBuilder
    private var bubble: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            if item.message.deleted {
                Label("Message deleted", systemImage: "nosign").font(.subheadline.italic()).foregroundStyle(DS.Palette.secondaryText)
            } else {
                if let image = item.localImage {
                    ZStack(alignment: .bottom) {
                        Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: 240, maxHeight: 300).clipped()
                        if let progress = item.uploadProgress, item.state == .sending {
                            UploadProgressView(progress: progress)
                                .padding(DS.Space.xs)
                                .background(.ultraThinMaterial)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
                } else if !item.message.media.isEmpty {
                    MediaGrid(media: item.message.media).frame(maxWidth: 240)
                }
                if let text = item.message.text, !text.isEmpty {
                    Text(text).foregroundStyle(isMine ? .white : DS.Palette.primaryText)
                }
            }
        }
        .padding(.horizontal, item.localImage == nil && item.message.media.isEmpty ? DS.Space.s : DS.Space.xxs)
        .padding(.vertical, item.localImage == nil && item.message.media.isEmpty ? DS.Space.xs : DS.Space.xxs)
        .background {
            let shape = BubbleShape(isMine: isMine, joinsPrevious: joinsPrevious, joinsNext: !isLastInGroup)
            if isMine && !item.message.deleted { shape.fill(DS.Brand.gradient) } else { shape.fill(DS.Palette.bubbleIncoming) }
        }
        .clipShape(BubbleShape(isMine: isMine, joinsPrevious: joinsPrevious, joinsNext: !isLastInGroup))
        .opacity(item.state == .sending ? 0.75 : 1)
        .contextMenu {
            if let text = item.message.text, !text.isEmpty {
                Button { UIPasteboard.general.string = text } label: { Label("Copy", systemImage: "doc.on.doc") }
            }
            if isMine && item.state == .sent && !item.message.deleted {
                Button(role: .destructive, action: onDelete) { Label("Delete for everyone", systemImage: "trash") }
            }
            if item.state == .failed {
                Button(action: onRetry) { Label("Retry", systemImage: "arrow.clockwise") }
                Button(role: .destructive, action: onDiscard) { Label("Discard", systemImage: "xmark") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isMine ? "You" : item.message.sender?.displayName ?? ""): \(item.message.text ?? (item.message.media.isEmpty && item.localImage == nil ? "" : "Photo"))")
    }

    @ViewBuilder
    private var footer: some View {
        switch item.state {
        case .failed:
            Button(action: onRetry) {
                Label("Not sent. Tap to retry", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.danger)
            }
            .buttonStyle(.plain)
        case .sending where item.localImage == nil:
            Text("Sending…").font(.caption2).foregroundStyle(DS.Palette.tertiaryText)
        default:
            if isLastInGroup {
                HStack(spacing: DS.Space.xxs) {
                    Text(item.message.createdAt.formatted(date: .omitted, time: .shortened))
                    if item.message.edited { Text("· Edited") }
                    if seen { Text("· Seen") }
                }
                .font(.caption2)
                .foregroundStyle(DS.Palette.tertiaryText)
                .padding(isMine ? .trailing : .leading, isMine ? DS.Space.xxs : 40)
            }
        }
    }
}

private struct DaySeparator: View {
    let date: Date
    var body: some View {
        Pill(text: Calendar.current.isDateInToday(date) ? "Today" : Calendar.current.isDateInYesterday(date) ? "Yesterday" : date.formatted(date: .abbreviated, time: .omitted))
            .padding(.vertical, DS.Space.s)
            .frame(maxWidth: .infinity)
    }
}

private struct TypingBubble: View {
    @State private var phase = 0.0
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(DS.Palette.secondaryText).frame(width: 7, height: 7)
                        .opacity(0.35 + 0.65 * abs(sin(phase + Double(i) * 0.6)))
                }
            }
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.s)
            .background(DS.Palette.bubbleIncoming, in: Capsule())
            .padding(.leading, 36)
            Spacer()
        }
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi } }
        .accessibilityLabel("Typing")
    }
}

#Preview {
    NavigationStack {
        ConversationView(conversationID: "c-ada", repository: MockMessagingRepository(), social: MockSocialRepository())
    }
    .environmentObject(DeepLinkRouter())
}
