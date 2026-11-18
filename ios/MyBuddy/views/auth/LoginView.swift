//
//  LoginView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import SwiftUI

struct LoginView: View {

    @Environment(\.dismiss) var dismiss

    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var password = ""

    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showProgress = false
    @State private var resetMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.l) {
                ScreenHeader(systemImage: "person.crop.circle", title: "Welcome Back", subtitle: "Login to your account")
                    .padding(.top, DS.Space.xl)

                VStack(spacing: DS.Space.s) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .dsField()

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(loginUser)
                        .dsField()

                    HStack {
                        Spacer()
                        Button("Forgot password?", action: sendReset)
                            .font(.footnote.weight(.medium))
                    }
                }

                LoadingButton(title: "Login", isLoading: showProgress, action: loginUser)
                    .disabled(email.isEmpty || password.isEmpty)

                NavigationLink {
                    RegisterView()
                } label: {
                    Text("Don't have an account? ").foregroundStyle(DS.Palette.secondaryText) + Text("Register").fontWeight(.semibold)
                }
                .font(.footnote)
            }
            .padding(.horizontal, DS.Space.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Login Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .alert(
            "Password reset",
            isPresented: Binding(get: { resetMessage != nil }, set: { if !$0 { resetMessage = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(resetMessage ?? "") }
        )
    }

    private func sendReset() {
        Task {
            do {
                try await auth.sendPasswordReset(email: email)
                resetMessage = String(localized: "auth.reset.sent", defaultValue: "If an account exists for that email, a reset link is on its way.")
            } catch {
                resetMessage = AppError.wrap(error).userMessage
            }
        }
    }

    func loginUser() {
        focus = nil
        showProgress = true
        auth.login(email: email, password: password) { error in
            showProgress = false
            if let error {
                alertMessage = error.localizedDescription
                showingAlert = true
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthViewModel.shared)
}
