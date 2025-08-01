//
//  FeedItemView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 23/07/2025.
//

import SwiftUI

struct FeedItemView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var feedItem: Feed;
    var likeAction: (_ feed: Feed) -> Void;
    var dislikeAction: (_ feed: Feed) -> Void;
    
    var body: some View {
        VStack(alignment: .leading) {
            
            HStack(spacing: 10) {

                if let contact = feedItem.contact {
                    ProfilePhoto(contact: contact, width: 40, height: 40)
                }

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
                    .foregroundStyle(
                        colorScheme == .dark ? Color(
                            red: 238,
                            green: 240,
                            blue: 243
                        ) : .black
                    )
            }
            .padding(.bottom)
                        
            HStack {
                
                Spacer()
                
                Button {
                    // like action
                    likeAction(feedItem)
                } label: {
                    HStack {
                        Text("\(feedItem.likes.abbreviated)")
                        Image(systemName: "heart")
                            .font(.system(size: 30))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button {
                    // unlike action
                    dislikeAction(feedItem)
                } label: {
                    HStack {
                        Text("\(feedItem.dislikes.abbreviated)")
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(.system(size: 30))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                
            }
        }
        .frame(maxWidth: .infinity)
        
    }
    
}

#Preview {
    
    let feedItem = Feed(
        context: PersistenceController.preview.container.viewContext
    )
    feedItem.content = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
    feedItem.likes = 91234
    feedItem.dislikes = 840305576
    
    return VStack {
        FeedItemView(
        feedItem: feedItem,
        likeAction: { _ in },
        dislikeAction: { _ in }
        )
    }.padding()
}
