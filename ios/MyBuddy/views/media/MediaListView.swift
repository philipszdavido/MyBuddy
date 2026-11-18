//
//  MediaListView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 21/07/2025.
//

import SwiftUI
import CoreData

struct MediaListView: View {

    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    )
    private var mediaList: FetchedResults<Media>

    let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]
    
    @State var isPresented: Bool = false
    @State var selectedMedia: Media? = nil

    var body: some View {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(mediaList, id: \.self) { media in
                        
                        //if media.type == "image" {
                            if let data = media.mediaData, let uiImage = UIImage(data: data) {
                                
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 200)
                                    .frame(height: 100)
                                    .padding(1)
                                    .clipped()
                                    .onTapGesture {
                                        
                                        withAnimation {
                                            isPresented = true
                                        }
                                        
                                    }
                                    .fullScreenCover(isPresented: $isPresented) {
                                        isPresented = false
                                    } content: {
                                        
                                        ViewMedia(media: media) {
                                            isPresented = false
                                        }
                                        
                                    }
                            }
                        //}
                    }
                }
            }
            

        
        
    }
}

#Preview {
    MediaListView()
        .environment(
            \.managedObjectContext,
             PersistenceController.preview
                .container.viewContext)
}
