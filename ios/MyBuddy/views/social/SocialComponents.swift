//
//  SocialComponents.swift
//  MyBuddy
//
//  Small building blocks shared by the social screens (feed, profile, comments, search, activity).
//  Styling follows the existing feed and contact rows.
//

import AVKit
import SwiftUI

/// Destinations reachable from social content, pushed on the tab's NavigationStack.
enum SocialRoute: Hashable {
    case profile(String)
    case post(String)
    case comments(String)
}

/// Round avatar: the photo when there is one, otherwise initials on a colour unique to the person.
/// Optional online dot and gradient ring (unread / new activity).
struct AvatarView: View {
    let user: UserSummary?
    var size: CGFloat = 40
    var online = false
    var ring = false

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
            .padding(ring ? max(2, size * 0.05) : 0)
            .background {
                if ring {
                    Circle().stroke(DS.Brand.ring, lineWidth: max(2, size * 0.045))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if online {
                    Circle()
                        .fill(DS.Palette.success)
                        .frame(width: size * 0.27, height: size * 0.27)
                        .overlay(Circle().stroke(DS.Palette.background, lineWidth: max(1.5, size * 0.045)))
                        .accessibilityLabel("Online")
                }
            }
            .accessibilityHidden(!online)
    }

    @ViewBuilder
    private var content: some View {
        if let url = user?.avatarURL {
            CachedAsyncImage(url: url, width: Int(size), height: Int(size))
        } else {
            ZStack {
                DS.AvatarPalette.gradient(for: user?.id ?? "?")
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private var initials: String {
        let parts = (user?.displayName ?? "?").split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// Name with verified badge and optional @username.
struct UserNameLabel: View {
    let user: UserSummary
    var showUsername = false

    var body: some View {
        HStack(spacing: 4) {
            Text(user.displayName).fontWeight(.semibold)
            if user.isVerified {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(DS.Palette.accent).font(.caption)
                    .accessibilityLabel("Verified")
            }
            if showUsername, let username = user.username {
                Text("@\(username)").foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
}

/// Rectangular remote image with a cache, fills its frame.
struct RemoteImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.15))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { failed = true; return }
        if let cached = ImageCache.shared.getCachedImage(for: url) { image = cached; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let decoded = UIImage(data: data) else { failed = true; return }
            ImageCache.shared.cache(image: decoded, for: url)
            image = decoded
        } catch {
            failed = true
        }
    }
}

/// One to four media items in a grid; videos play inline.
struct MediaGrid: View {
    let media: [MediaItem]

    var body: some View {
        let items = Array(media.prefix(4))
        Group {
            if items.count == 1 {
                cell(items[0]).aspectRatio(min(max(items[0].aspectRatio ?? 1, 0.6), 1.8), contentMode: .fit)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                    ForEach(items) { item in cell(item).aspectRatio(1, contentMode: .fill) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    @ViewBuilder
    private func cell(_ item: MediaItem) -> some View {
        switch (item.status, item.kind) {
        case (.ready, .video):
            if let url = item.videoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .accessibilityLabel("Video")
            } else {
                RemoteImage(url: item.displayURL)
            }
        case (.ready, .image):
            RemoteImage(url: item.displayURL).accessibilityLabel("Photo")
        case (.failed, _):
            ZStack { Rectangle().fill(Color.gray.opacity(0.15)); Label("Couldn't process", systemImage: "exclamationmark.triangle").font(.caption) }
        default:
            ZStack { Rectangle().fill(Color.gray.opacity(0.15)); VStack { ProgressView(); Text("Processing…").font(.caption) } }
        }
    }
}

extension View {
    /// Standard error alert bound to an optional message.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Something went wrong", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } }),
              actions: { Button("OK", role: .cancel) {} }, message: { Text(message.wrappedValue ?? "") })
    }
}
