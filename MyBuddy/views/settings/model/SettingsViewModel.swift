//
//  SettingsViewModel.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 25/07/2025.
//

import Foundation
import UIKit

class SettingsViewModel: ObservableObject {
    
    static let shared = SettingsViewModel()
    private let chatRoomViewModel = ChatRoomViewModel.shared
    
    @Published var loading = false
    
    func editPhoto(userId: String, image: UIImage, completion: @escaping (String?) -> Void) {
        
        DispatchQueue.main.async {
            self.loading = true
        }
        
        chatRoomViewModel.uploadToCloudinary(image: image) { result, data in
            
            DispatchQueue.main.async {
                self.loading = false
            }

            switch result {
            case .success(let result):
                // call callback with url
                self.chatRoomViewModel
                    .updateContactUrl(userId: userId, url: result) { error in
                        DispatchQueue.main.async {
                            completion(result)
                        }
                    }
                
            case .failure(_):
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
            
        }
    }
    
    func deletePhoto(imageUrl: String, _ completion: () -> Void) {
        
        loading = true
        
        let publicId =  extractPublicId(from: imageUrl)
        
        if let publicId {
            chatRoomViewModel.deleteImageFromCloudinary(publicId: publicId)
        }
        
        loading = false
        
    }
    
    func extractPublicId(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        
        // Find the part after /upload/
        guard let uploadRange = url.absoluteString.range(of: "/upload/") else { return nil }
        
        let pathAfterUpload = url.absoluteString[uploadRange.upperBound...]
        
        // Remove version and extension
        // v1234567890/path/to/file.jpg → path/to/file
        let components = pathAfterUpload.split(separator: "/").dropFirst() // Drop version (v...)
        guard let lastComponent = components.last else { return nil }
        
        let fileName = lastComponent.split(separator: ".").first ?? lastComponent
        
        let path = components.dropLast() + [fileName]
        return path.joined(separator: "/")
    }

    
}
