//
//  FeedViewModel.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 21/07/2025.
//

import Foundation
import Firebase
import FirebaseFirestore


class FeedViewModel: ObservableObject {
    let shared = FeedViewModel()
    private var db = Firestore.firestore()
    private let coreDataUtils = CoreDataUtils.shared

    func insertFeed() {
        
    }
    
}
