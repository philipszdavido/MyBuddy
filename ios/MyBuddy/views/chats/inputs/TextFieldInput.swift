//
//  TextFieldInput.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 23/07/2025.
//

import SwiftUI

struct TextFieldInput: View {
    
    @Binding var text: String
    var colorScheme: ColorScheme

    var body: some View {
        TextField("Message", text: $text)
            .padding(10)
            .background(colorScheme == .light ? Color(white: 0.9) : Color(white: 0.2))
            .foregroundStyle(colorScheme == .light ? .black : .white)
            .clipShape(Capsule())
            .multilineTextAlignment(.leading)
        
    }
}

#Preview {
    TextFieldInput(text: .constant("uiop"), colorScheme: .dark)
}
