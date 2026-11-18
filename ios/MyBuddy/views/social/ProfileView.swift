//
//  ProfileView.swift
//  MyBuddy
//
//  A user's profile: avatar, name, bio, counts, follow/unfollow (or request for private accounts)
//  and their posts.
//

import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: Profile?
    @Published private(set) var posts: [Post] = []
    @Published private(set) var unavailable = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    private var cursor: String?
    private var reachedEnd = false
    let userID: String
    private let repository: SocialRepository

    init(repository: SocialRepository, userID: String) {
        self.repository = repository
        self.userID = userID
    }

    func load() async {
        do {
            profile = try await repository.profile(userID: userID)
            cursor = nil
            reachedEnd = false
            posts = []
            await loadMorePosts()
        } catch AppError.notFound {
            unavailable = true
        } catch {
            report(error)
        }
    }

    func loadMorePosts() async {
        guard !reachedEnd else { return }
        do {
            let page = try await repository.posts(by: userID, cursor: cursor)
            posts += page.items.filter { p in !posts.contains { $0.id == p.id } }
            cursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
        } catch AppError.validation {
            reachedEnd = true // private account: posts are not visible
        } catch {
            report(error)
        }
    }

    func toggleFollow() async {
        guard let rel = profile?.relationship, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if rel.following || rel.requested {
                try await repository.unfollow(userID: userID)
            } else {
                _ = try await repository.follow(userID: userID)
            }
            await load()
        } catch { report(error) }
    }

    func react(_ reaction: ReactionKind, on post: Post) async {
        guard let i = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let next: ReactionKind? = post.myReaction == reaction ? nil : reaction
        let before = posts[i]
        posts[i] = SocialFeedViewModel.applying(next, to: before)
        do { _ = try await repository.react(postID: post.id, next) }
        catch { if let j = posts.firstIndex(where: { $0.id == post.id }) { posts[j] = before }; report(error) }
    }

    private func report(_ error: Error) {
        let e = AppError.wrap(error)
        if case .cancelled = e { return }
        errorMessage = e.userMessage
    }
}

struct ProfileView: View {
    @StateObject private var model: ProfileViewModel
    @State private var tab: Tab = .posts

    private enum Tab: String, CaseIterable { case posts = "Posts", media = "Media" }

    init(repository: SocialRepository, userID: String) {
        _model = StateObject(wrappedValue: ProfileViewModel(repository: repository, userID: userID))
    }

    var body: some View {
        ScrollView {
            if model.unavailable {
                BrandEmptyState(systemImage: "person.fill.questionmark", title: "Profile unavailable",
                                message: "This account doesn't exist or isn't available.")
                    .padding(.top, 80)
            } else if let profile = model.profile {
                VStack(alignment: .leading, spacing: 0) {
                    header(profile)
                    Picker("Content", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, DS.Space.m)
                    .padding(.vertical, DS.Space.m)
                    content(profile)
                }
            } else {
                VStack(spacing: DS.Space.m) {
                    Rectangle().fill(Color(uiColor: .systemFill)).frame(height: 150)
                    SkeletonList(rows: 3)
                }
                .shimmering()
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(model.profile?.user.username.map { "@\($0)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await model.load() }
        .task { await model.load() }
        .errorAlert($model.errorMessage)
    }

    // MARK: Header

    @ViewBuilder
    private func header(_ p: Profile) -> some View {
        ZStack(alignment: .bottomLeading) {
            cover(p)
            AvatarView(user: p.user, size: 96)
                .padding(4)
                .background(DS.Palette.background, in: Circle())
                .offset(x: DS.Space.m, y: 48)
        }
        .padding(.bottom, 48)

        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.Space.xxs) {
                        Text(p.user.displayName).font(.title2.weight(.bold))
                        if p.user.isVerified { Image(systemName: "checkmark.seal.fill").foregroundStyle(DS.Palette.accent).accessibilityLabel("Verified") }
                        if p.visibility == .private { Image(systemName: "lock.fill").font(.subheadline).foregroundStyle(DS.Palette.secondaryText).accessibilityLabel("Private account") }
                    }
                    if let username = p.user.username { Text("@\(username)").foregroundStyle(DS.Palette.secondaryText) }
                }
                Spacer()
            }
            if let bio = p.bio, !bio.isEmpty { Text(bio).font(.body) }
            HStack(spacing: DS.Space.m) {
                if let location = p.location { Label(location, systemImage: "mappin.and.ellipse").lineLimit(1) }
                if let website = p.website, let url = URL(string: website) {
                    Link(destination: url) { Label(url.host() ?? website, systemImage: "link").lineLimit(1) }
                }
                Label("Joined \(p.joinedAt.formatted(.dateTime.month(.abbreviated).year()))", systemImage: "calendar").lineLimit(1)
            }
            .font(.footnote)
            .foregroundStyle(DS.Palette.secondaryText)

            HStack(spacing: DS.Space.l) {
                stat(p.postsCount, "Posts")
                stat(p.followersCount, "Followers")
                stat(p.followingCount, "Following")
            }
            .padding(.vertical, DS.Space.xxs)

            if let rel = p.relationship {
                followButton(rel)
                if rel.isContact || rel.followedBy {
                    Label(rel.isContact ? "In your contacts" : "Follows you",
                          systemImage: rel.isContact ? "person.crop.circle.badge.checkmark" : "person.fill.checkmark")
                        .font(.caption).foregroundStyle(DS.Palette.secondaryText)
                }
            }
        }
        .padding(.horizontal, DS.Space.m)
    }

    @ViewBuilder
    private func cover(_ p: Profile) -> some View {
        ZStack {
            if let url = p.coverURL {
                RemoteImage(url: url)
            } else {
                // A different colour from the avatar so the two don't blend.
                DS.AvatarPalette.gradient(for: p.id + "·cover")
                Circle().fill(.white.opacity(0.16)).frame(width: 220).blur(radius: 30).offset(x: 120, y: -30)
            }
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func followButton(_ rel: Relationship) -> some View {
        let title = rel.following ? "Following" : rel.requested ? "Requested" : rel.followedBy ? "Follow back" : "Follow"
        if rel.following || rel.requested {
            Button(title) { Haptics.selection(); Task { await model.toggleFollow() } }
                .buttonStyle(.secondary)
                .disabled(model.isWorking)
        } else {
            Button(title) { Haptics.success(); Task { await model.toggleFollow() } }
                .buttonStyle(.gradient)
                .disabled(model.isWorking || rel.blocking)
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        HStack(spacing: DS.Space.xxs) {
            Text("\(value.abbreviated)").font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(DS.Palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ profile: Profile) -> some View {
        let locked = profile.visibility == .private && !(profile.relationship?.following ?? true)
        if model.posts.isEmpty {
            BrandEmptyState(systemImage: locked ? "lock.fill" : "square.stack",
                            title: locked ? "This account is private" : "No posts yet",
                            message: locked ? "Follow to see their posts." : "When \(profile.user.displayName) shares something, it'll appear here.")
                .padding(.vertical, DS.Space.xl)
        } else if tab == .posts {
            LazyVStack(spacing: 0) {
                ForEach(model.posts) { post in
                    PostCardView(post: post, onReact: { r in Task { await model.react(r, on: post) } }, onSave: {}, onRepost: {}, onDelete: {})
                        .padding(.horizontal, DS.Space.m)
                        .padding(.vertical, DS.Space.m)
                        .onAppear { if post.id == model.posts.last?.id { Task { await model.loadMorePosts() } } }
                    Divider().padding(.leading, DS.Space.m)
                }
            }
        } else {
            let media = model.posts.flatMap { post in post.media.map { (post.id, $0) } }
            if media.isEmpty {
                Text("No photos or videos yet").foregroundStyle(DS.Palette.secondaryText).frame(maxWidth: .infinity).padding(.vertical, DS.Space.xl)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(media, id: \.1.id) { postID, item in
                        NavigationLink(value: SocialRoute.post(postID)) {
                            RemoteImage(url: item.urls["thumb"] ?? item.displayURL)
                                .aspectRatio(1, contentMode: .fill)
                                .overlay(alignment: .topTrailing) {
                                    if item.kind == .video { Image(systemName: "play.fill").font(.caption).foregroundStyle(.white).padding(6).shadow(radius: 2) }
                                }
                        }
                    }
                }
            }
        }
    }
}

/// Lets a single Button switch between bordered and bordered-prominent styles.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

#Preview {
    NavigationStack { ProfileView(repository: MockSocialRepository(), userID: "ada") }
}
