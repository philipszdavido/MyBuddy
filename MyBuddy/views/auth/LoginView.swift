//
//  LoginView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import SwiftUI
import FirebaseAuth

struct LoginView: View {

    @Environment(\.dismiss) var dismiss

    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
    
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showProgress = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image("welcome_art")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
            
            Text("Welcome Back")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Login to your account")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            VStack(spacing: 15) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(Color(white: 0.15))
                    .cornerRadius(10)
                    .foregroundColor(.white)
                
                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(white: 0.15))
                    .cornerRadius(10)
                    .foregroundColor(.white)
            }
            .padding(.horizontal)
            
            Button(action: {
                loginUser()
            }) {
                
                    if !showProgress {
                        
                        Text("Login")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                    }
                    
                    if showProgress {
                        
                        ProgressView()
                            .foregroundColor(.white)
                        
                    }
                
            }
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(10)
            .padding(.horizontal)
            
            NavigationLink {
                RegisterView()
            } label: {
                Text("Don't have an account? Register")
                    .font(.footnote)
                    .foregroundColor(.blue)
                    .padding(.top)

            }

            
            Spacer(minLength: 30)
        }
        .background(Color.black.ignoresSafeArea())
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Login Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    func loginUser() {
        
        showProgress = true

        auth.login(email: email, password: password) { error in
            
            if error == nil {
                showProgress = false
                dismiss()
            } else {

                if let error = error {
                    showProgress = false
                    alertMessage = error.localizedDescription
                }
                
                showProgress = false
                showingAlert.toggle()
                
            }
        }
        
    }
    
}

#Preview {
    NavigationStack {
        LoginView()
    }
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthViewModel())
}

