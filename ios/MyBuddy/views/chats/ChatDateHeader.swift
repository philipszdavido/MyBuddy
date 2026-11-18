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
    let color = UIColor(red: 22 / 255.0, green: 23 / 255.0, blue: 23 / 255.0, alpha: 1.0)
    
    init(_ date: Date) {
        self.date = date
    }
    
    var body: some View {
        Text(date.formatted(date: .abbreviated, time: .standard))
            .font(.caption)
            .foregroundColor(colorScheme == .dark ? .black : .white)
            .padding(.vertical, 5)
            .padding(.horizontal, 15)
            .background(colorScheme == .dark ? .white : Color(uiColor: color))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    ChatDateHeader(Date.now)
}
