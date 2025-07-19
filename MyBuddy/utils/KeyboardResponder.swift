//
//  KeyboardResponder.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI
import Combine

class KeyboardResponder: ObservableObject {
    @Published var currentHeight: CGFloat = 0
    private var cancellable: AnyCancellable?

    init() {
        cancellable = Publishers.Merge(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                .compactMap { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height },
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in CGFloat(0) }
        )
        .receive(on: RunLoop.main)
        .assign(to: \.currentHeight, on: self)
    }
}

class KeyboardResponderV2: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    private var cancellableSet: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification))
            .sink { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    self.keyboardHeight = keyboardFrame.height
                }
            }
            .store(in: &cancellableSet)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { _ in
                self.keyboardHeight = 0
            }
            .store(in: &cancellableSet)
    }
}

struct KeyboardView: View {
    @StateObject private var keyboard = KeyboardResponderV2()
    @State private var text = ""

    var body: some View {
        VStack {
            VStack {
                Spacer()
                TextField("Enter something...", text: $text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
            }

            // View above the keyboard
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button("Send") {
                        // Action
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(.horizontal)
                }
                .padding(.bottom, keyboard.keyboardHeight)
                .animation(.easeOut(duration: 0.25), value: keyboard.keyboardHeight)
            }
        }
        .ignoresSafeArea(.keyboard) // Prevent system from pushing views up
    }
}
