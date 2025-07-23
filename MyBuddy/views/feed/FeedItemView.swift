//
//  FeedItemView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 23/07/2025.
//

import SwiftUI

struct FeedItemView: View {
    
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
    
    let feedItem = Feed(
        context: PersistenceController.preview.container.viewContext
    )
    feedItem.content = "jhbjhb"
    
    return VStack {
        FeedItemView(
        feedItem: feedItem,
        likeAction: { _ in },
        dislikeAction: { _ in }
        )
    }.padding()
}
