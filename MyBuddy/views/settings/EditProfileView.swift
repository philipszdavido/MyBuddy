//
//  EditProfileView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 25/07/2025.
//

import SwiftUI
import PhotosUI
import CoreData

struct EditProfileView: View {
    
    @Environment(\.managedObjectContext) var managedObjectContext
    @ObservedObject private var settingsViewModel = SettingsViewModel.shared
    @ObservedObject var contact: Contact
    var userId: String
    
    @State private var showPhotoOptions = false
    @State private var showPhotoPicker = false
    @State private var selectedImage: UIImage?
    @State private var photoAction: PhotoAction?
    
    enum PhotoAction {
        case camera, photoLibrary
    }
    
    var body: some View {
        List {
            profilePhotoSection
            
            Section("Name") {
                NavigationLink {
                    // Navigate to name editing screen
                } label: {
                    Text(contact.displayName ?? "No Name")
                }
            }

            Section("Phone Number") {
                NavigationLink {
                    // Navigate to phone editing screen
                } label: {
                    Text(String(contact.phoneNumber))
                }
            }
        }
        .sheet(isPresented: $showPhotoPicker, onDismiss: {
            
        }) {
            photoPickerContent
        }
        .confirmationDialog("Choose Photo Option", isPresented: $showPhotoOptions) {
            Button("Take Photo") {
                photoAction = .camera
                showPhotoPicker = true
            }
            Button("Choose from Library") {
                photoAction = .photoLibrary
                showPhotoPicker = true
            }
            if contact.photo != nil {
                Button("Remove Photo", role: .destructive) {
                    removePhoto()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private var profilePhotoSection: some View {
        HStack {
            Spacer()

                VStack {
                    
                    ZStack {
                        
                        if settingsViewModel.loading {
                            
                            if let photo = contact.photo,
                               let data = photo.mediaData,
                               let image = UIImage(data: data) {
                                
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 150, height: 150)
                                    .clipShape(Circle())
                                
                            } else {
                                
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 150, height: 150)
                                
                            }
                        } else {
                            ProfilePhoto(contact: contact, width: 150, height: 150)
                        }
                        
                        if settingsViewModel.loading {
                            ProgressView()
                        }
                        
                    }
                    
                    Button("Edit") {
                        showPhotoOptions = true
                    }
                    .font(.system(size: 16, weight: .bold))
                    .padding(.top, 10)
                
            }
            
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder
    private var photoPickerContent: some View {

        switch photoAction {

        case .camera:
            CameraView(selectedImage: $selectedImage)

        case .photoLibrary:
            PhotoPickerView(selectedImage: $selectedImage) { uIImage in

                withAnimation {

                    // Save image to contact model
                    if contact.photo == nil {
                        let media = Media(context: managedObjectContext)
                        contact.photo = media
                    }
                    
                    contact.photo?.mediaData = uIImage.jpegData(compressionQuality: 0.8)
                    contact.photo?.url = nil
                                                            
                    // edit in firestore
                    settingsViewModel
                        .editPhoto(userId: userId, image: uIImage) { url in

                        if let url {
                            contact.photo?.url = url
                            save()
                        }
                        
                    }
                    
                }
                
            }
            
        case .none:
            EmptyView()
        }
    }
        
    private func removePhoto() {
        
        DispatchQueue.main.async {

            withAnimation {
                
                if let url = contact.photo?.url {
                    
                    settingsViewModel.deletePhoto(imageUrl: url) {
                        
                        contact.photo = nil
                        save()
                        
                    }
                    
                }
                
            }

        }
        
    }
    
    func save() {
        
        do {
            
            try managedObjectContext.save()
            contact.objectWillChange.send()
            
        } catch {
            print("Error saving context.")
        }
        
    }
    
}

#Preview {
    
    let context = PersistenceController.preview.container.viewContext
    
    let user = Contact(
        context: context
    )
    
    let photo = Media(context: context)
    photo.mediaData = Mock.generateMockImageData()
    photo.url = "https://res.cloudinary.com/dwbggi96z/image/upload/v1753525367/chat_images/ff9xwenzckj7mpggunyj.jpg"
    
    user.displayName = "Nna"
    user.phoneNumber = 90987654321
    user.photo = photo
    
    return NavigationStack {
        EditProfileView(
            contact: user,
            userId: "hKeVPZjSlafWOEdZ59Mtlv3bB5i1"
        )
    }.environment(
        \.managedObjectContext,
         PersistenceController.preview.container
            .viewContext)
}

