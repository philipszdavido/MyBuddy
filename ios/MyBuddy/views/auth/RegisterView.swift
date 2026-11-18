//
//  RegisterView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 13/07/2025.
//

import SwiftUI

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
        ScrollView {
            VStack(spacing: DS.Space.l) {
                VStack(spacing: DS.Space.xs) {
                    Text("Create Account").font(.title.bold())
                    Text("Sign up to get started").font(.subheadline).foregroundStyle(DS.Palette.secondaryText)
                }
                .padding(.top, DS.Space.l)

                VStack(spacing: DS.Space.s) {
                    TextField("Display Name", text: $name)
                        .textContentType(.name)
                        .dsField()

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .dsField()

                    TextField("Phone Number", text: $phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .dsField()

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .dsField()

                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .dsField()

                    Text("Your phone number lets your contacts find you. It isn't shown to people who don't already have it.")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LoadingButton(title: "Register", isLoading: showProgress, action: registerUser)

                HStack(spacing: DS.Space.xxs) {
                    Text("Already have an account?")
                        .foregroundStyle(DS.Palette.secondaryText)
                    NavigationLink("Login", destination: LoginView())
                        .fontWeight(.semibold)
                }
                .font(.footnote)
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.bottom, DS.Space.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Registration Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    func registerUser() {
        guard password == confirmPassword else {
            alertMessage = String(localized: "auth.register.mismatch", defaultValue: "Passwords do not match.")
            showingAlert = true
            return
        }
        guard let phoneNumber = Int64(phoneNumber.filter(\.isNumber)) else {
            alertMessage = String(localized: "auth.register.phone", defaultValue: "Phone number must be provided")
            showingAlert = true
            return
        }
        showProgress = true
        auth.register(email: email, password: password, phoneNumber: phoneNumber, displayName: name) { error in
            showProgress = false
            if let error {
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        RegisterView()
    } .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthViewModel.shared)
}
