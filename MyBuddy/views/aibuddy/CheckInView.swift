//
//  CheckInView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 26/06/2025.
//

import SwiftUI

struct CheckInView: View {
    @AppStorage("lastCheckInDate") var lastCheckInDate: String = ""
    @State private var input = ""
    @State private var submitted = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Daily Check-in")
                .font(.title)
            if !submitted && !isCheckedInToday() {
                TextEditor(text: $input)
                    .frame(height: 150)
                    .border(Color.gray)
                Button("Submit") {
                    submitted = true
                    lastCheckInDate = currentDateString()
                }
            } else {
                Text("You've checked in today ✅")
            }
        }.padding()
    }

    func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    func isCheckedInToday() -> Bool {
        return lastCheckInDate == currentDateString()
    }
}

#Preview {
    CheckInView()
}
