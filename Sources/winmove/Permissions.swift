//  Permissions.swift
//  Prompt for Accessibility access (required for AX window mutation AND for
//  CGEvent taps that listen to keyDown).

import AppKit
import ApplicationServices

enum Permissions {
    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Poll until the user grants Accessibility, then call `ready`.
    /// Also wires up a notification subscription so we notice grants promptly.
    static func waitForAccessibility(_ ready: @escaping () -> Void) {
        if accessibilityTrusted(prompt: true) { ready(); return }

        let center = DistributedNotificationCenter.default()
        var token: NSObjectProtocol?
        token = center.addObserver(forName: Notification.Name("com.apple.accessibility.api"),
                                   object: nil, queue: .main) { _ in
            if accessibilityTrusted(prompt: false) {
                if let t = token { center.removeObserver(t) }
                ready()
            }
        }
        // Fallback polling (some systems don't emit the notification reliably).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            poll(ready: ready, token: { token }, clear: { token = nil })
        }
    }

    private static func poll(ready: @escaping () -> Void,
                             token: @escaping () -> NSObjectProtocol?,
                             clear: @escaping () -> Void) {
        if accessibilityTrusted(prompt: false) {
            if let t = token() { DistributedNotificationCenter.default().removeObserver(t) }
            clear()
            ready()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            poll(ready: ready, token: token, clear: clear)
        }
    }
}
