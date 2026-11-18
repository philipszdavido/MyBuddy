//
//  Brand.swift
//  MyBuddy
//
//  The craft layer on top of DesignSystem: brand gradient, per-person avatar colours, press feedback,
//  haptics, loading skeletons and chat bubble shapes. These details are what make the app feel
//  finished rather than merely functional.
//

import SwiftUI
import UIKit

extension DS {
    enum Brand {
        static let violet = Color(red: 0.42, green: 0.36, blue: 1.0)
        static let sky = Color(red: 0.25, green: 0.66, blue: 0.96)
        static let pink = Color(red: 0.98, green: 0.36, blue: 0.56)

        /// Primary brand gradient (hero areas, outgoing bubbles, story rings).
        static let gradient = LinearGradient(colors: [violet, sky], startPoint: .topLeading, endPoint: .bottomTrailing)
        /// Warmer accent gradient for "new" and unread rings.
        static let ring = AngularGradient(colors: [pink, violet, sky, pink], center: .center)
    }

    /// Stable, pleasant colour pairs for initials avatars, chosen from the person's id.
    enum AvatarPalette {
        private static let pairs: [(Color, Color)] = [
            (Color(red: 0.99, green: 0.55, blue: 0.40), Color(red: 0.96, green: 0.33, blue: 0.47)),
            (Color(red: 0.36, green: 0.62, blue: 1.00), Color(red: 0.44, green: 0.40, blue: 0.98)),
            (Color(red: 0.24, green: 0.80, blue: 0.64), Color(red: 0.13, green: 0.62, blue: 0.75)),
            (Color(red: 1.00, green: 0.75, blue: 0.30), Color(red: 0.98, green: 0.52, blue: 0.24)),
            (Color(red: 0.73, green: 0.45, blue: 0.99), Color(red: 0.55, green: 0.34, blue: 0.94)),
            (Color(red: 0.98, green: 0.45, blue: 0.70), Color(red: 0.86, green: 0.34, blue: 0.86)),
            (Color(red: 0.40, green: 0.78, blue: 0.96), Color(red: 0.24, green: 0.55, blue: 0.92)),
            (Color(red: 0.55, green: 0.80, blue: 0.36), Color(red: 0.29, green: 0.66, blue: 0.42)),
        ]

        static func gradient(for id: String) -> LinearGradient {
            // FNV-1a plus a final avalanche: deterministic across launches (String.hashValue is seeded per
            // process) and well spread, so similar short ids ("ada", "bola") land on different colours.
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
            hash ^= hash >> 33; hash = hash &* 0xff51afd7ed558ccd; hash ^= hash >> 33
            let pair = pairs[Int(hash % UInt64(pairs.count))]
            return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Press feedback

/// Subtle scale-down while pressed; for cards, rows and icon buttons.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { .init() }
}

/// Gradient capsule for the main call to action on hero screens.
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(DS.Brand.gradient.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .shadow(color: DS.Brand.violet.opacity(isEnabled ? 0.35 : 0), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GradientButtonStyle {
    static var gradient: GradientButtonStyle { .init() }
}

// MARK: - Skeletons

/// Animated sheen for placeholder shapes while content loads.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.4)
                }
                .mask(content)
                .blendMode(.plusLighter)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .accessibilityHidden(true)
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// Rounded grey block used to compose skeletons.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(uiColor: .systemFill))
            .frame(width: width, height: height)
    }
}

/// Placeholder rows for lists (inbox, contacts, activity).
struct SkeletonList: View {
    var rows = 6
    var avatar: CGFloat = 52

    var body: some View {
        VStack(spacing: DS.Space.l) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: DS.Space.s) {
                    Circle().fill(Color(uiColor: .systemFill)).frame(width: avatar, height: avatar)
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        SkeletonBlock(width: CGFloat(110 + (i * 37) % 90), height: 13)
                        SkeletonBlock(width: CGFloat(170 + (i * 53) % 110), height: 11)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.top, DS.Space.m)
        .shimmering()
    }
}

/// Placeholder post cards for the feed.
struct SkeletonPosts: View {
    var body: some View {
        VStack(spacing: DS.Space.xl) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack(spacing: DS.Space.s) {
                        Circle().fill(Color(uiColor: .systemFill)).frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 120, height: 13)
                            SkeletonBlock(width: 70, height: 10)
                        }
                    }
                    SkeletonBlock(height: 13)
                    SkeletonBlock(width: 220, height: 13)
                    if i == 0 { SkeletonBlock(height: 200, radius: DS.Radius.l) }
                }
            }
        }
        .padding(DS.Space.m)
        .shimmering()
    }
}

// MARK: - Chat bubble shape

/// Bubble with large corners, except the corners facing a neighbouring bubble from the same sender,
/// which tighten, so a run of messages reads as one group (as in the best messaging apps).
struct BubbleShape: Shape {
    var isMine: Bool
    var joinsPrevious: Bool
    var joinsNext: Bool

    func path(in rect: CGRect) -> Path {
        let big: CGFloat = 20, small: CGFloat = 6
        let topLeading = !isMine && joinsPrevious ? small : big
        let bottomLeading = !isMine && joinsNext ? small : big
        let topTrailing = isMine && joinsPrevious ? small : big
        let bottomTrailing = isMine && joinsNext ? small : big
        return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: topLeading, bottomLeading: bottomLeading, bottomTrailing: bottomTrailing, topTrailing: topTrailing), style: .continuous)
    }
}

// MARK: - Misc

/// Small pill label (date separators, "New", counts).
struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DS.Palette.secondaryText)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
    }
}

/// Large circular icon used in empty states.
struct EmptyStateIcon: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 84, height: 84)
            .background(DS.Brand.gradient, in: Circle())
            .shadow(color: DS.Brand.violet.opacity(0.3), radius: 16, y: 8)
            .accessibilityHidden(true)
    }
}

/// Empty state with a brand icon, title, message and optional action.
struct BrandEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Space.m) {
            EmptyStateIcon(systemImage: systemImage)
            VStack(spacing: DS.Space.xs) {
                Text(title).font(.title3.weight(.bold))
                Text(message).font(.subheadline).foregroundStyle(DS.Palette.secondaryText).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.gradient)
                    .frame(maxWidth: 240)
                    .padding(.top, DS.Space.xs)
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .frame(maxWidth: .infinity)
    }
}
