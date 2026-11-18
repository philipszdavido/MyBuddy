//
//  SearchView.swift
//  MyBuddy
//
//  Search people and posts (with #hashtag support) and browse trending hashtags.
//

import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    enum Scope: String, CaseIterable, Identifiable { case people = "People", posts = "Posts"; var id: String { rawValue } }

    @Published var query = ""
    @Published var scope: Scope = .people
    @Published private(set) var people: [UserSummary] = []
    @Published private(set) var posts: [Post] = []
    @Published private(set) var trending: [String] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?
    private let repository: SocialRepository

    init(repository: SocialRepository) { self.repository = repository }

    func loadTrending() async { trending = (try? await repository.trendingHashtags()) ?? [] }

    /// Debounced by the caller's `.task(id:)`: cancelled when the query changes again.
    func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else { people = []; posts = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            switch scope {
            case .people: people = try await repository.searchUsers(q, cursor: nil).items
            case .posts: posts = try await repository.searchPosts(q, cursor: nil).items
            }
        } catch {
            let e = AppError.wrap(error)
            if case .cancelled = e { return }
            errorMessage = e.userMessage
        }
    }
}

struct SearchView: View {
    @StateObject private var model: SearchViewModel

    init(repository: SocialRepository) {
        _model = StateObject(wrappedValue: SearchViewModel(repository: repository))
    }

    var body: some View {
        List {
            Picker("Search", selection: $model.scope) {
                ForEach(SearchViewModel.Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if model.query.isEmpty {
                if !model.trending.isEmpty {
                    Section("Trending") {
                        ForEach(model.trending, id: \.self) { tag in
                            Button("#\(tag)") { model.scope = .posts; model.query = "#\(tag)" }
                        }
                    }
                }
            } else if model.isSearching {
                ProgressView()
            } else {
                switch model.scope {
                case .people:
                    if model.people.isEmpty { Text("No people found").foregroundStyle(.secondary) }
                    ForEach(model.people) { user in
                        NavigationLink(value: SocialRoute.profile(user.id)) {
                            HStack(spacing: 10) {
                                AvatarView(user: user, size: 36)
                                VStack(alignment: .leading) {
                                    UserNameLabel(user: user)
                                    if let username = user.username { Text("@\(username)").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                case .posts:
                    if model.posts.isEmpty { Text("No posts found").foregroundStyle(.secondary) }
                    ForEach(model.posts) { post in
                        NavigationLink(value: SocialRoute.post(post.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                UserNameLabel(user: post.author).font(.subheadline)
                                Text(post.text ?? "").lineLimit(3)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Search")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "People, posts, #hashtags")
        .textInputAutocapitalization(.never)
        .task { await model.loadTrending() }
        .task(id: "\(model.scope.rawValue)|\(model.query)") { await model.search() }
        .errorAlert($model.errorMessage)
    }
}

#Preview {
    NavigationStack { SearchView(repository: MockSocialRepository()) }
}
