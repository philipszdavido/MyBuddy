//
//  SwipeBackWrapper.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 16/07/2025.
//

import Foundation
import SwiftUI

struct SwipeBackWrapper<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let hosting = UIHostingController(rootView: content)
        let nav = UINavigationController(rootViewController: hosting)
        nav.interactivePopGestureRecognizer?.delegate = context.coordinator
        hosting.navigationItem.hidesBackButton = true
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let hosting = uiViewController.viewControllers.first as? UIHostingController<Content> {
            hosting.rootView = content
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            return true // Allow swipe back
        }
    }
}
