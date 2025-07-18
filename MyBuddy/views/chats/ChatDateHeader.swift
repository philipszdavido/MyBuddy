//
//  ChatDateHeader.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI

struct ChatDateHeader: View {
    @Environment(\.colorScheme) var colorScheme
    let date: Date
    
    init(_ date: Date) {
        self.date = date
    }
    
    var body: some View {
        Text(date.formatted(date: .abbreviated, time: .standard))
            .font(.caption)
            .foregroundColor(colorScheme == .dark ? .black : .white)
            .padding(.vertical, 5)
            .padding(.horizontal, 5)
            .background(colorScheme == .dark ? .white : .black)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    ChatDateHeader(Date.now)
}
