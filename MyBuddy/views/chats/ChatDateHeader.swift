//
//  ChatDateHeader.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI

struct ChatDateHeader: View {
    let date: Date
    
    init(_ date: Date) {
        self.date = date
    }
    
    var body: some View {
        Text(date.formatted(date: .complete, time: .complete))
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    ChatDateHeader(Date.now)
}
