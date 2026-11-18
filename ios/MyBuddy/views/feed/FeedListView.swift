//
//  FeedListView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 21/07/2025.
//

import SwiftUI

struct ViewOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Feed tab. On the MyBuddy API backend it shows the social feed (media, comments, profiles, search,
/// activity); on the Firebase backend it keeps the original Core Data feed below.
struct FeedListView: View {
    var body: some View {
        if let social = AppContainer.shared.socialRepository {
            SocialFeedView(repository: social)
        } else {
            LegacyFeedListView()
        }
    }
}

struct LegacyFeedListView: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    @StateObject private var feedViewModel = FeedViewModel()
    @ObservedObject private var blockedUsers = BlockedUsersStore.shared
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        animation: .default
    ) var feedList: FetchedResults<Feed>
    
    @State var messageText = ""
    @State private var isChatBarVisible = true
    
    @State private var showChatBar = false
        
    var body: some View {
        VStack {

            HStack {
                // Bottom Input Bar
                ChatInputBar(
                    text: $messageText,
                    colorScheme: colorScheme,
                    onSend: {
                        sendFeed()
                    },
                    onImageSend: { _, _ in }
                )
            }

            if feedList.isEmpty {
                ContentUnavailableView(
                    "No posts yet",
                    systemImage: "newspaper",
                    description: Text("Posts from your contacts will show up here.")
                )
                .frame(maxHeight: .infinity)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    
                    LazyVStack {
                        ForEach(feedList.filter { !blockedUsers.phones.contains($0.contact?.phoneNumber ?? 0) }) { feedItem in
                            FeedItemView(
                                feedItem: feedItem,
                                myReaction: feedViewModel.myReactions[feedItem.id ?? ""],
                                likeAction: likeAction,
                                dislikeAction: dislikeAction
                            )
                                .padding(.bottom)
                                .padding(.horizontal)
                            
                            Divider()
                                .padding(.bottom)
                            
                        }
                    }
                    
                }
                .refreshable {
                    await feedViewModel.refresh()
                }
                
            }
                        
        }
        .hideKeyboardOnTap()
        .task {
            // Single bounded listener on the user's own feed; cancelled when the view disappears.
            await feedViewModel.syncFeed()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { feedViewModel.errorMessage != nil },
                set: { if !$0 { feedViewModel.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(feedViewModel.errorMessage ?? "") }
        )

    }
    
    func sendFeed() {
        
        let text = messageText
        Task {
            if await feedViewModel.publish(content: text) {
                messageText = ""
            }
        }
        
    }
    
    func likeAction(_ feed: Feed) {
        
        
        feedViewModel.react(to: feed, .like)
        
    }
    
    func dislikeAction(_ feed: Feed) {
        
        feedViewModel.react(to: feed, .dislike)

    }
}

#Preview {
    
    FeedListView()
        .environment(
            \.managedObjectContext,
             PersistenceController.preview.container
                .viewContext)
}


