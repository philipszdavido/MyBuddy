//
//  Contact.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 18/07/2025.
//

import Foundation

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
