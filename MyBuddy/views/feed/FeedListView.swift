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

            ScrollViewReader { proxy in
                ScrollView {
                    
                    VStack {
                        ForEach(feedList) { feedItem in
                            FeedItemView(
                                feedItem: feedItem,
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
                
            }
                        
        }
        .hideKeyboardOnTap()
        .onAppear {
            
            feedViewModel.listenToFeed()
            
        }

    }
    
    func sendFeed() {
        
        feedViewModel.insertFeed(content: messageText) { error in
            
        }
        
    }
    
    func likeAction(_ feed: Feed) {
        
        
        if let contact = feed.contact, let id = feed.id {

            feedViewModel.likeFeed(contact: contact, feedId: id)
            
        }
        
    }
    
    func dislikeAction(_ feed: Feed) {
        
        if let contact = feed.contact, let id = feed.id {
            
            feedViewModel.dislikeFeed(contact: contact, feedId: id)
            
        }

    }
}

#Preview {
    
    FeedListView()
        .environment(
            \.managedObjectContext,
             PersistenceController.preview.container
                .viewContext)
}


