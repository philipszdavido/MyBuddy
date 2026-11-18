//
//  DesignSystem.swift
//  MyBuddy
//
//  One place for the app's visual language: spacing, radii, semantic colours (adaptive light/dark)
//  and the few reusable controls every screen shares. Screens use these instead of literal values so
//  the app stays consistent: system typography, generous whitespace, one accent colour.
//

import SwiftUI

enum DS {
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 18
        static let bubble: CGFloat = 18
    }

    enum Palette {
        static let accent = Color.accentColor
        static let background = Color(uiColor: .systemBackground)
        static let groupedBackground = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemBackground)
        static let fieldBackground = Color(uiColor: .tertiarySystemFill)
        static let separator = Color(uiColor: .separator)
        static let primaryText = Color(uiColor: .label)
        static let secondaryText = Color(uiColor: .secondaryLabel)
        static let tertiaryText = Color(uiColor: .tertiaryLabel)
        static let danger = Color(uiColor: .systemRed)
        static let success = Color(uiColor: .systemGreen)
        /// Incoming chat bubble.
        static let bubbleIncoming = Color(uiColor: .secondarySystemBackground)
    }

    enum Icon {
        static let action: CGFloat = 17
    }
}

// MARK: - Buttons

/// Full-width primary action: brand gradient capsule with press feedback.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GradientButtonStyle().makeBody(configuration: configuration)
    }
}

/// Full-width tinted button for secondary actions (red for destructive roles).
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let tint = configuration.role == .destructive ? DS.Palette.danger : DS.Palette.accent
        return configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0.12), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var secondary: SecondaryButtonStyle { .init() } }

/// Primary button that shows a spinner while `isLoading`.
struct LoadingButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(.white) }
            }
        }
        .buttonStyle(.primary)
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}

// MARK: - Fields

/// Rounded, filled input field used on auth and edit screens.
struct FieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DS.Space.m)
            .frame(minHeight: 54)
            .background(DS.Palette.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func dsField() -> some View { modifier(FieldBackground()) }
}

// MARK: - Layout helpers

/// Centered header (icon, title, subtitle) for onboarding and auth screens.
struct ScreenHeader: View {
    var systemImage: String? = nil
    var image: String? = nil
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: DS.Space.s) {
            if let image {
                Image(image).resizable().scaledToFit().frame(width: 96, height: 96)
                    .accessibilityHidden(true)
            } else if let systemImage {
                EmptyStateIcon(systemImage: systemImage)
                    .padding(.bottom, DS.Space.xs)
            }
            Text(title).font(.system(.title, design: .rounded).bold()).multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(DS.Palette.secondaryText).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Small capsule count badge (unread counts).
struct CountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(DS.Palette.accent, in: Capsule())
                .accessibilityLabel("\(count) unread")
        }
    }
}

/// Determinate progress for uploads, with a caption.
struct UploadProgressView: View {
    let progress: Double
    var label = "Uploading"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ProgressView(value: min(max(progress, 0), 1))
                .tint(DS.Palette.accent)
            Text(progress >= 1 ? "Processing…" : "\(label) \(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(DS.Palette.secondaryText)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress >= 1 ? "Processing" : "\(label), \(Int(progress * 100)) percent")
    }
}

/// Settings-style row: tinted icon tile + title (+ optional value).
struct SettingsRow: View {
    let title: String
    let systemImage: String
    var tint: Color = DS.Palette.accent
    var value: String? = nil

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
            if let value {
                Spacer()
                Text(value).foregroundStyle(DS.Palette.secondaryText)
            }
        }
    }
}

extension Date {
    /// Compact timestamp for lists: time today, weekday this week, date otherwise.
    var listTimestamp: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(self) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: self, to: .now).day, days < 7 {
            return formatted(.dateTime.weekday(.wide))
        }
        return formatted(date: .numeric, time: .omitted)
    }
}
