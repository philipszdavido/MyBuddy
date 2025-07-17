//
//  WelcomeView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 13/07/2025.
//

import SwiftUI

struct WelcomeView: View {
    
    @State var present = false
    
    var body: some View {
        VStack(spacing: 20) {
            
            Spacer()
            
            // Top illustration image
            Image(uiImage: UIImage(named: "welcome_art") ?? UIImage())
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)

            // Title
            Text("Welcome to\nMyBuddy")
                .font(.title2)
                .multilineTextAlignment(.center)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            // Subtitle
            Text("A simple, secure and reliable way for\nyou to connect with your contacts")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Terms note
            Text("Tap “Agree & Continue” to accept the MyBuddy ")
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Text("Terms of Service")
                .font(.footnote)
                .foregroundColor(.blue)

            // Action button
            DefaultButton(action: {
                present = true
            })

            // Bottom suggestion
//            Text("Not a business? Try ")
//                .foregroundColor(.gray)
//                .font(.footnote)
//            + Text("WhatsApp Messenger")
//                .foregroundColor(.blue)
//                .font(.footnote)

            Spacer(minLength: 20)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationDestination(isPresented: $present) {
            RegisterView()
        }
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
}

struct DefaultButton : View {
    
    var action: () -> Void

    var body: some View {
        Button(action: {
            action()
        }) {
            Text("Agree & Continue")
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
                .padding(.horizontal)
        }
    }
}

