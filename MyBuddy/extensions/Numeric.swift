//
//  Numeric.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 01/08/2025.
//

import Foundation

extension Formatter {
    static let abbreviated: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.locale = Locale.current
        return formatter
    }()
}

extension Numeric {
    var abbreviated: String {
        let num = Double("\(self)") ?? 0

        switch num {
        case 1_000_000_000...:
            return "\(Formatter.abbreviated.string(from: NSNumber(value: num / 1_000_000_000)) ?? "0")B"
        case 1_000_000...:
            return "\(Formatter.abbreviated.string(from: NSNumber(value: num / 1_000_000)) ?? "0")M"
        case 1_000...:
            return "\(Formatter.abbreviated.string(from: NSNumber(value: num / 1_000)) ?? "0")K"
        default:
            return "\(self)"
        }
    }
}
