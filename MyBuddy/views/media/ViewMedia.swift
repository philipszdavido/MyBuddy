//
//  ViewMedia.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 21/07/2025.
//

import SwiftUI

struct ViewMedia: View {
    
    var media: Media
    var closeAction: () -> Void

    var body: some View {
        VStack {
            
            HStack {
                Spacer()
                Button {
                    closeAction()
                } label: {
                    Image(systemName: "xmark")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(.top)
            .padding(.bottom, 30)

            Spacer()
            
            if let type = media.type {
                if type == "image" {
                    if let imageData = media.mediaData,
                       let uiImage = UIImage(data: imageData) {
                        //HStack {
                            //Spacer()
                            Image(uiImage: uiImage)
                                //.resizable()
                                //.scaledToFit()
//                                .frame(
//                                    maxWidth: .infinity,
//                                    maxHeight: .infinity
//                                )
                            //Spacer()
                        //}
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    }
}

#Preview {
    ViewMedia(
        media: Media(
            context: PersistenceController.preview.container.viewContext
        ), closeAction: {}
    )
}
