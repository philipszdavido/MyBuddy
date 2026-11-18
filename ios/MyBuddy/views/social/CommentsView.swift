//
//  CommentsView.swift
//  MyBuddy
//
//  Comment thread of a post: top-level comments (newest first) with expandable replies, likes,
//  delete, and a reply bar. Optionally shows the post itself on top (post detail / deep link).
//

import SwiftUI

@MainActor
final class CommentsViewModel: ObservableObject {
    @Published private(set) var comments: [Comment] = []
    @Published private(set) var replies: [String: [Comment]] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private var cursor: String?
    private(set) var reachedEnd = false
    let postID: String
    private let repository: SocialRepository

    init(repository: SocialRepository, postID: String) {
        self.repository = repository
        self.postID = postID
    }

    func reload() async {
        cursor = nil
        reachedEnd = false
        comments = []
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repository.comments(postID: postID, cursor: cursor)
            comments += page.items.filter { c in !comments.contains { $0.id == c.id } }
            cursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
        } catch { report(error) }
    }

    func loadReplies(_ comment: Comment) async {
        do { replies[comment.id] = try await repository.replies(commentID: comment.id, cursor: nil).items }
        catch { report(error) }
    }

    /// Returns true when posted. The client id makes a retry after a timeout safe.
    func send(_ text: String, replyingTo parent: Comment?, clientID: String) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        do {
            let comment = try await repository.addComment(postID: postID, text: body, parentID: parent?.id, clientID: clientID)
            if let root = comment.rootID {
                replies[root, default: []].append(comment)
                if let i = comments.firstIndex(where: { $0.id == root }) { comments[i].replies += 1 }
            } else {
                comments.insert(comment, at: 0)
            }
            return true
        } catch {
            report(error)
            return false
        }
    }

    func toggleLike(_ comment: Comment) async {
        let next: ReactionKind? = comment.myReaction == .like ? nil : .like
        do {
            let counts = try await repository.reactToComment(id: comment.id, next)
            update(comment.id) { $0.likes = counts.likes; $0.myReaction = counts.mine }
        } catch { report(error) }
    }

    func delete(_ comment: Comment) async {
        do {
            try await repository.deleteComment(id: comment.id)
            update(comment.id) { $0.deleted = true; $0.text = nil }
        } catch { report(error) }
    }

    private func update(_ id: String, _ change: (inout Comment) -> Void) {
        if let i = comments.firstIndex(where: { $0.id == id }) { change(&comments[i]) }
        for (root, list) in replies {
            if let i = list.firstIndex(where: { $0.id == id }) { change(&replies[root]![i]) }
        }
    }

    private func report(_ error: Error) {
        let e = AppError.wrap(error)
        if case .cancelled = e { return }
        errorMessage = e.userMessage
    }
}

struct CommentsView: View {
    let repository: SocialRepository
    let postID: String
    var header: Post? = nil

    @StateObject private var model: CommentsViewModel
    @State private var draft = ""
    @State private var replyingTo: Comment?
    @State private var draftID = UUID().uuidString
    @State private var sending = false
    @FocusState private var focused: Bool

    init(repository: SocialRepository, postID: String, header: Post? = nil) {
        self.repository = repository
        self.postID = postID
        self.header = header
        _model = StateObject(wrappedValue: CommentsViewModel(repository: repository, postID: postID))
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if let header {
                    PostCardView(post: header, onReact: { _ in }, onSave: {}, onRepost: {}, onDelete: {})
                        .listRowSeparator(.hidden)
                }
                if model.comments.isEmpty && !model.isLoading {
                    Text("No comments yet. Start the conversation.").foregroundStyle(.secondary)
                }
                ForEach(model.comments) { comment in
                    CommentRow(comment: comment, onLike: { Task { await model.toggleLike(comment) } },
                               onReply: { replyingTo = comment; focused = true },
                               onDelete: { Task { await model.delete(comment) } })
                        .onAppear { if comment.id == model.comments.last?.id { Task { await model.loadMore() } } }
                    if comment.replies > 0 {
                        if let replies = model.replies[comment.id] {
                            ForEach(replies) { reply in
                                CommentRow(comment: reply, onLike: { Task { await model.toggleLike(reply) } },
                                           onReply: { replyingTo = reply; focused = true },
                                           onDelete: { Task { await model.delete(reply) } })
                                    .padding(.leading, 36)
                            }
                        } else {
                            Button("View \(comment.replies) \(comment.replies == 1 ? "reply" : "replies")") {
                                Task { await model.loadReplies(comment) }
                            }
                            .font(.caption)
                            .padding(.leading, 36)
                        }
                    }
                }
                if model.isLoading { ProgressView() }
            }
            .listStyle(.plain)
            .refreshable { await model.reload() }

            VStack(spacing: 4) {
                if let replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.author?.displayName ?? "comment")").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { self.replyingTo = nil }.font(.caption)
                    }
                }
                HStack {
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task {
                            sending = true
                            if await model.send(draft, replyingTo: replyingTo, clientID: draftID) {
                                draft = ""
                                replyingTo = nil
                                draftID = UUID().uuidString
                            }
                            sending = false
                        }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send comment")
                }
            }
            .padding()
        }
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.reload() }
        .errorAlert($model.errorMessage)
    }
}

struct CommentRow: View {
    let comment: Comment
    var onLike: () -> Void
    var onReply: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let author = comment.author {
                NavigationLink(value: SocialRoute.profile(author.id)) { AvatarView(user: author, size: 30) }.buttonStyle(.plain)
            } else {
                AvatarView(user: nil, size: 30)
            }
            VStack(alignment: .leading, spacing: 4) {
                if comment.deleted {
                    Text("Comment deleted").italic().foregroundStyle(.secondary)
                } else {
                    if let author = comment.author { UserNameLabel(user: author).font(.subheadline) }
                    Text(comment.text ?? "")
                }
                HStack(spacing: 16) {
                    Text(comment.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                    if !comment.deleted {
                        Button("Reply", action: onReply).font(.caption)
                        if comment.canDelete { Button("Delete", role: .destructive, action: onDelete).font(.caption) }
                    }
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            if !comment.deleted {
                Button(action: onLike) {
                    VStack(spacing: 0) {
                        Image(systemName: comment.myReaction == .like ? "heart.fill" : "heart")
                        if comment.likes > 0 { Text("\(comment.likes.abbreviated)").font(.caption2) }
                    }
                    .frame(minWidth: 30, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Like comment")
                .accessibilityValue("\(comment.likes) likes")
            }
        }
    }
}

#Preview {
    NavigationStack { CommentsView(repository: MockSocialRepository(), postID: "p1") }
}
