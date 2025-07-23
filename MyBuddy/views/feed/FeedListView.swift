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

struct FeedListView: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    private let listener = FirestoreListener()
    private let feedViewModel = FeedViewModel()
    
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
                Text("Feed")
                    .font(.system(size: 30, weight: .bold))
                Spacer()
                
                if !isChatBarVisible {
                    HStack {
                        Button {
                            withAnimation(.bouncy) {
                                showChatBar.toggle()
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        
                    }
                }
                
            }.padding(.horizontal)
            
            if showChatBar && !isChatBarVisible {
                withAnimation(.easeIn) {
                    ChatInputBar(
                        text: $messageText,
                        colorScheme: colorScheme,
                        onSend: {
                            sendFeed()
                        }
                    )
                }
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    
                    // Bottom Input Bar
                    ChatInputBar(
                        text: $messageText,
                        colorScheme: colorScheme,
                        onSend: {
                            sendFeed()
                        }
                    )

//                    .onScrollVisibilityChange(threshold: 0.5) { isVisible in
//                        isChatBarVisible = isVisible
//                    }
                    
                    
                    VStack {
                        ForEach(feedList) { feedItem in
                            FeedItem(
                                feedItem: feedItem,
                                likeAction: likeAction,
                                dislikeAction: dislikeAction
                            )
                                .padding(.bottom)
                            
                        }
                    }
                    .padding(.horizontal)
                }
                .coordinateSpace(name: "scrollView")
                
            }
                        
        }
        .hideKeyboardOnTap()
        .onAppear {
            
            // /user_feed/1234567890/posts/dH4oRCEW3JQCv6ILAmsG
            feedViewModel.listenToFeed()
            
        }

    }
    
    func sendFeed() {
        feedViewModel.insertFeed(content: messageText) { error in
            
        }
    }
    
    func likeAction(_ feed: Feed) {
        
        
        if let contact = feed.contact, let id = feed.id {
            print("like", contact, id)
            feedViewModel.likeFeed(contact: contact, feedId: id)
            
        }
        
    }
    
    func dislikeAction(_ feed: Feed) {
        
        if let contact = feed.contact, let id = feed.id {
            
            feedViewModel.dislikeFeed(contact: contact, feedId: id)
            
        }

    }
}

struct FeedItem: View {
    
    var feedItem: Feed;
    var likeAction: (_ feed: Feed) -> Void;
    var dislikeAction: (_ feed: Feed) -> Void;
    
    var body: some View {
        VStack(alignment: .leading) {
            
            HStack(spacing: 10) {
                Circle()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    
                    if let contact = feedItem.contact {
                        Text(contact.displayName ?? "")
                    }
                    
                    if let timestamp = feedItem.timestamp {
                        Text(timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                }
            }
            
            VStack {
                Text(feedItem.content ?? "")
            }
            .padding(.bottom)
            
            Divider()
            
            HStack {
                
                Spacer()
                
                Button {
                    // like action
                    likeAction(feedItem)
                } label: {
                    HStack {
                        Text("\(feedItem.likes)")
                        Image(systemName: "heart")
                        
                            .font(.system(size: 30))
                    }
                }
                
                Button {
                    // unlike action
                    dislikeAction(feedItem)
                } label: {
                    HStack {
                        Text("\(feedItem.dislikes)")
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(.system(size: 30))
                    }
                }
                
                
            }
        }
        .frame(maxWidth: .infinity)
        
    }
}

#Preview {
    FeedListView()
        .environment(
            \.managedObjectContext,
             PersistenceController.preview.container
                .viewContext)
}

#Preview {
    
    let feedItem = Feed(
        context: PersistenceController.preview.container.viewContext
    )
    feedItem.content = "jhbjhb"
    
    return FeedItem(
        feedItem: feedItem,
        likeAction: { _ in },
        dislikeAction: { _ in }
    )
}


