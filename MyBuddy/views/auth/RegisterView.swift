//
//  RegisterView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 13/07/2025.
//

import SwiftUI
import FirebaseAuth

struct RegisterView: View {
    
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var phoneNumber = ""
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
            
            Text("Create Account")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Sign up to get started")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            VStack(spacing: 15) {
                
                TextField("Display Name", text: $name)
                    .textContentType(.givenName)
                    .keyboardType(.default)
                    .padding()
                    .background(Color(white: 0.15))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(Color(white: 0.15))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                TextField("Phone Number", text: $phoneNumber)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .padding()
                    .background(Color(white: 0.15))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(white: 0.15))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                SecureField("Confirm Password", text: $confirmPassword)
                    .padding()
                    .background(Color(white: 0.15))
                    .cornerRadius(10)
                    .foregroundColor(.white)
            }
            .padding(.horizontal)
            
            Button(action: {
                registerUser()
            }) {
                
                if !showProgress {
                    Text("Register")
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

            
            HStack {
                Text("Already have an account?")
                    .font(.footnote)
                    .foregroundColor(.blue)
                    .padding(.top)

                NavigationLink("Login", destination: LoginView())
                    .font(.footnote)
                    .foregroundColor(.blue)
                    .padding(.top)
            }

            Spacer(minLength: 30)
        }
        .background(Color.black.ignoresSafeArea())
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Registration Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    func registerUser() {

        showProgress = true

        // Add Firebase registration logic here
        guard password == confirmPassword else {
            alertMessage = "Passwords do not match."
            showingAlert = true
            showProgress = false
            return
        }
        
        guard let phoneNumber = Int64(phoneNumber) else {
            alertMessage = "Phone number must be provided"
            showingAlert = true
            showProgress = false
            return
        }

        auth
            .register(
                email: email,
                password: password,
                phoneNumber: phoneNumber,
                displayName: name,
                completion: {error in
                    if error != nil {
                        showProgress = false

                    }
                    
                    if let error = error {
                        showProgress = false
                        alertMessage = error.localizedDescription;
                        showingAlert.toggle()
                    }
                }
            )
    }
}

#Preview {
    NavigationStack {
        RegisterView()
    } .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthViewModel())
}
