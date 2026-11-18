//
//  WelcomeView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 13/07/2025.
//

import SwiftUI

struct WelcomeView: View {

    @State var present = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: DS.Space.l) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Your people,\nall in one place.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Welcome to MyBuddy — chats, groups and moments with the contacts who matter.")
                        .font(.body)
                        .foregroundStyle(DS.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                VStack(alignment: .leading, spacing: DS.Space.m) {
                    feature("bubble.left.and.bubble.right.fill", "Private chats and groups")
                    feature("photo.stack.fill", "Share photos, videos and updates")
                    feature("lock.shield.fill", "You decide who sees what")
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                Spacer(minLength: 0)

                VStack(spacing: DS.Space.s) {
                    DefaultButton(action: { Haptics.tap(); present = true })
                    termsNote
                }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.top, DS.Space.l)
            .padding(.bottom, DS.Space.m)
        }
        .background(DS.Palette.background.ignoresSafeArea())
        .navigationDestination(isPresented: $present) { RegisterView() }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.1)) { appeared = true } }
    }

    private var hero: some View {
        ZStack {
            DS.Brand.gradient
            // Soft light blobs give the gradient depth.
            Circle().fill(.white.opacity(0.18)).frame(width: 260).blur(radius: 40).offset(x: -110, y: -60)
            Circle().fill(DS.Brand.pink.opacity(0.35)).frame(width: 220).blur(radius: 50).offset(x: 130, y: 70)
            Image("welcome_art")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .padding(DS.Space.l)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 44, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
                .scaleEffect(appeared ? 1 : 0.85)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 290)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 36, bottomTrailingRadius: 36, style: .continuous))
        .ignoresSafeArea(edges: .top)
    }

    private func feature(_ icon: String, _ title: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 34, height: 34)
                .background(DS.Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.medium))
        }
    }

    @ViewBuilder
    private var termsNote: some View {
        Group {
            if let terms = LegalLinks.terms {
                Text("By continuing you accept the [Terms of Service](\(terms.absoluteString)).")
            } else {
                Text("By continuing you accept the MyBuddy Terms of Service.")
            }
        }
        .font(.footnote)
        .foregroundStyle(DS.Palette.secondaryText)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
}

struct DefaultButton: View {

    var action: () -> Void

    var body: some View {
        Button("Agree & Continue", action: action)
            .buttonStyle(.gradient)
    }
}
