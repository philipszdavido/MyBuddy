// AI Buddy is disabled in this build: nothing in the app links to it, it returns placeholder replies,
// and the OpenAI call has no key (a key must never ship in the app; use a server-side proxy).
// Define the compilation condition AI_BUDDY to compile it again.
#if AI_BUDDY
//
//  ReminderView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 26/06/2025.
//

import SwiftUI

class ReminderViewModel: ObservableObject {
    @Published var reminders: [String] = []

    func addReminder(_ reminder: String) {
        reminders.append(reminder)
        save()
    }

    func save() {
        UserDefaults.standard.set(reminders, forKey: "reminders")
    }

    func load() {
        reminders = UserDefaults.standard.stringArray(forKey: "reminders") ?? []
    }

    init() { load() }
}

struct ReminderView: View {
    @StateObject private var viewModel = ReminderViewModel()
    @State private var newReminder = ""

    var body: some View {
        VStack {
            TextField("Add a reminder", text: $newReminder)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            Button("Add") {
                viewModel.addReminder(newReminder)
                newReminder = ""
            }
            List(viewModel.reminders, id: \.self) {
                Text($0)
            }
        }.navigationTitle("Reminders")
    }
}

#Preview {
    ReminderView()
}
#endif
