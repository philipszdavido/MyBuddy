//
//  Array.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 14/07/2025.
//

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        var chunks: [[Element]] = []
        var index = 0
        while index < self.count {
            let chunk = Array(self[index..<Swift.min(index + size, self.count)])
            chunks.append(chunk)
            index += size
        }
        return chunks
    }
}
