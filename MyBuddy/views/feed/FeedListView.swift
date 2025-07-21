//
//  FeedListView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 21/07/2025.
//

import SwiftUI

struct FeedListView: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    private let listener = FirestoreListener()
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    ) var feedList: FetchedResults<Feed>
    
    @State var messageText = ""
    
    var body: some View {
        VStack {
            
            ScrollViewReader { proxy in
                ScrollView {
                    
                    VStack {
                        HStack {
                            Text("Feed")
                                .font(.system(size: 50, weight: .bold))
                            Spacer()
                        }

                    }.padding(.horizontal)
                    
                    
                    VStack {
                        ForEach(feedList) { feedItem in
                            FeedItem(feedItem: feedItem)
                                .padding(.bottom)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            Spacer()
            
            // Bottom Input Bar
            ChatInputBar(
                text: $messageText,
                colorScheme: colorScheme,
                onSend: {
                }
            )
            
        }
        .onAppear {
            listener.listenToCollection(name: "") { DocumentChangeType, QueryDocumentSnapshot in
                
            }
        }

    }
}

struct FeedItem: View {
    
    var feedItem: Feed;
    
    var body: some View {
        VStack(alignment: .leading) {
            
            HStack(spacing: 10) {
                Circle()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text("User")
                    Text("Monday")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
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
                } label: {
                    HStack {
                        Text("\(feedItem.likes)")
                        Image(systemName: "heart")
                        
                            .font(.system(size: 30))
                    }
                }
                
                Button {
                    // unlike action
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
    
    return FeedItem(feedItem: feedItem)
}


