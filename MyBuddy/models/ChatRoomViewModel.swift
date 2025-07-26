//
//  ChatRoomViewModel.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import Firebase
import FirebaseStorage
import FirebaseFirestore
import Foundation
import CryptoKit

class ChatRoomViewModel: ObservableObject {

    private var db = Firestore.firestore()
    private let coreDataUtils = CoreDataUtils.shared
    
    static let shared = ChatRoomViewModel()

    init() {}
    
    func sendMessage(
        chatId: String,
        currentUserId: String,
        recipientUserId: String,
        messageText: String,
        recipientUserPhoneNumber: Int64,
        currentUserPhoneNumber: Int64,
        mediaType: FileType = .text,
        mediaUrl: String? = nil,
        mediaData: Data? = nil
    ) {

        let chatRef = db.collection("chats").document(chatId)
        let messageRef = chatRef.collection("messages").document()

        let messageContent = messageText
        let timestamp = Timestamp()

        self.coreDataUtils.insertChatMsg(
            id: chatId,
            currentUserId: currentUserId,
            recipientUserId: recipientUserId,
            lastMessage: messageContent,
            lastSenderId: currentUserId,
            lastTimestamp: timestamp.dateValue(),
            updatedAt: timestamp.dateValue(),
            recipientUserPhoneNumber: recipientUserPhoneNumber,
            currentUserPhoneNumber: currentUserPhoneNumber,
            lastSenderPhoneNumber: currentUserPhoneNumber,
            type: mediaType.rawValue
        )
        
        self.coreDataUtils.insertMessage(
            id: messageRef.documentID,
            chatId: chatId,
            senderId: currentUserId,
            recipientId: recipientUserId,
            content: messageContent,
            timestamp: timestamp.dateValue(),
            type: mediaType.rawValue,
            mediaUrl: mediaUrl,
            mediaData: mediaData,
            recipientPhoneNumber: recipientUserPhoneNumber,
            senderPhoneNumber: currentUserPhoneNumber,
            seen: false,
            sent: false
        )
        
        chatRef.getDocument { snapshot, error in
                                    
            if snapshot?.exists == false {
                
                // Chat doesn't exist – create it
                chatRef.setData([
                    "participants": [currentUserId, recipientUserId],
                    "lastMessage": messageContent,
                    "lastSenderId": currentUserId,
                    "lastTimestamp": timestamp,
                    "updatedAt": timestamp,
                    "recipientUserPhoneNumber": recipientUserPhoneNumber,
                    "currentUserPhoneNumber": currentUserPhoneNumber,
                    "lastSenderPhoneNumber": currentUserPhoneNumber,
                    "chatId": chatId,
                    "type": mediaType.rawValue
                ])
                
                
            } else {
                
                // Chat exists – update lastMessage
                chatRef.updateData([
                    "lastMessage": messageContent,
                    "lastSenderId": currentUserId,
                    "lastTimestamp": timestamp,
                    "updatedAt": timestamp,
                    "recipientUserPhoneNumber": recipientUserPhoneNumber,
                    "currentUserPhoneNumber": currentUserPhoneNumber,
                    "lastSenderPhoneNumber": currentUserPhoneNumber,
                    "chatId": chatId,
                    "type": mediaType.rawValue
                ])
                                
            }

            // Then add the message
            messageRef.setData([
                "senderId": currentUserId,
                "recipientId": recipientUserId,
                "content": messageContent,
                "timestamp": timestamp,
                "type": mediaType.rawValue,
                "mediaUrl": mediaUrl ?? "",
                "recipientPhoneNumber": recipientUserPhoneNumber,
                "senderPhoneNumber": currentUserPhoneNumber,
                "chatId": chatId,
                "seen": false,
                "sent": true
            ])
                        
        }

    }
    
    func sendMediaMessage(
        imageData: Data,
        chatDetails: ChatDetails
    ) {

        sendMessage(
            chatId: chatDetails.chatId,
            currentUserId: chatDetails.currentUserId,
            recipientUserId: chatDetails.recipientUserId,
            messageText: chatDetails.messageText,
            recipientUserPhoneNumber: chatDetails.recipientUserPhoneNumber,
            currentUserPhoneNumber: chatDetails.currentUserPhoneNumber,
            
            mediaType: chatDetails.fileType,
            mediaUrl: chatDetails.mediaUrl,
            mediaData: imageData

        )
        
    }

    func uploadImage(_ image: UIImage, completion: @escaping (Result<String, Error>, Data?) -> Void) {
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "ImageConversion", code: 0, userInfo: nil)), nil)
            return
        }

        let storageRef = Storage.storage().reference()
        let imageID = UUID().uuidString
        let imageRef = storageRef.child("images/\(imageID).jpg")

        imageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                completion(.failure(error), nil)
                return
            }

            imageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error), nil)
                    return
                }

                guard let downloadURL = url else {
                    completion(.failure(NSError(domain: "URLNotFound", code: 0, userInfo: nil)), nil)
                    return
                }
                
                completion(.success(downloadURL.absoluteString), imageData)
                
            }
        }
    }
    
    func uploadToCloudinary(image: UIImage, completion: @escaping (Result<String, Error>, Data?) -> Void) {
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "ConversionError", code: -1)), nil)
            return
        }

        let cloudName = "dwbggi96z"
        let uploadPreset = "chat_uploads"
        let url = URL(string: "https://api.cloudinary.com/v1_1/\(cloudName)/image/upload")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n")
        data.append("Content-Type: image/jpeg\r\n\r\n")
        data.append(imageData)
        data.append("\r\n--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"upload_preset\"\r\n\r\n")
        data.append("\(uploadPreset)\r\n")
        data.append("--\(boundary)--\r\n")

        request.httpBody = data

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error), nil)
                return
            }

            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let url = json["secure_url"] as? String
            else {
                completion(.failure(NSError(domain: "UploadFailed", code: -2)), nil)
                return
            }

            completion(.success(url), imageData)
        }.resume()
    }

    func fetchMediaFromFirestoreAndCache() {

        db.collection("media").getDocuments { snapshot, error in
            if let docs = snapshot?.documents {
                for doc in docs {
                    if let urlStr = doc.data()["url"] as? String,
                       let url = URL(string: urlStr) {
                        
                        // Download the media
                        URLSession.shared.dataTask(with: url) { data, _, _ in
                            // if let data = data {
                                // Save to Core Data
                            // }
                        }.resume()
                    }
                }
            }
        }
    }
    
    func fetchMediaFromUrlAndCache(url: String, completion: @escaping (Data?, Error?) -> Void) {
        if let url = URL(string: url) {
            print(url)
            URLSession.shared.dataTask(with: URLRequest(url: url)) { data, response, error in
                if let error {
                    print("Download error: \(error.localizedDescription)")
                    completion(nil, error)
                    return
                }
                                
                if let data {
                    print(data)
                    completion(data, nil)
                } else {
                    print("No data received")
                    completion(nil, nil)
                }
            }.resume()
        }
    }
    
    func updateContactUrl(
        userId: String,
        url: String,
        completion: @escaping (Error?) -> Void
    ) {

        let userRef = db.collection("users").document(userId)
        
        let fields = [
            "url" : url
        ]
        
        userRef.updateData(fields) { error in
            
            if let error {
                completion(error)
            }
            
            completion(nil)
            
        }

    }
    
    func deleteImageFromCloudinary(publicId: String) {

        let cloudName = CLOUDINARY_cloudName
        let apiKey = CLOUDINARY_apiKey
        let apiSecret = CLOUDINARY_apiSecret
        
        let timestamp = Int(Date().timeIntervalSince1970)
        
        // 1. Generate signature
        let signatureBase = "public_id=\(publicId)&timestamp=\(timestamp)\(apiSecret)"
        let signature = Insecure.SHA1.hash(data: Data(signatureBase.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        
        // 2. Prepare the body
        let params = [
            "public_id": publicId,
            "api_key": apiKey,
            "timestamp": "\(timestamp)",
            "signature": signature
        ]
        
        let bodyString = params.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)!
        
        // 3. Send the request
        var request = URLRequest(url: URL(string: "https://api.cloudinary.com/v1_1/\(cloudName)/image/destroy")!)
        request.httpMethod = "POST"
        request.httpBody = bodyString
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let data {
                print("Response:", String(data: data, encoding: .utf8) ?? "")
            } else if let error {
                print("Error:", error)
            }
        }
        
        task.resume()
    }

}
