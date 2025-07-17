//
//  openAIUtils.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 26/06/2025.
//

import Foundation

let YOUR_API_KEY = ""

func callOpenAI(prompt: String, completion: @escaping (String) -> Void) {
    guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("Bearer " + YOUR_API_KEY, forHTTPHeaderField: "Authorization")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let json: [String: Any] = [
        "model": "gpt-3.5-turbo",
        "messages": [["role": "user", "content": prompt]]
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: json)

    URLSession.shared.dataTask(with: request) { data, response, error in
        
        if let data = data,
           let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
           let reply = decoded.choices.first?.message.content {
            completion(reply)
        }
        
        if let response = response {
            print(response)
        }
        
        if let error = error {
            print(error)
        }
        
    }.resume()
}

struct OpenAIResponse: Codable {
    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let role: String
        let content: String
    }

    let choices: [Choice]
}
