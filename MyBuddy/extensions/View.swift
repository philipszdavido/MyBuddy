//
//  View.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 18/07/2025.
//

import Foundation
import SwiftUICore
import UIKit

extension View {
        
    func backgroundTheme(colorScheme: ColorScheme) -> some View {
        return self.background(colorScheme == .dark ? .black : .white)
    }
    
    func foregroundTheme(colorScheme: ColorScheme) -> some View {
        return self.foregroundStyle(colorScheme == .dark ? .white : .black)
    }
    
    func hideKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
}
