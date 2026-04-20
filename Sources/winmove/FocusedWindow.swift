//  FocusedWindow.swift
//  A minimal wrapper around the focused window of the frontmost app.

import AppKit
import ApplicationServices

struct FocusedWindow {
    let element: AXUIElement
    let pid: pid_t

    static func current() -> FocusedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        guard let win: AXUIElement = appEl.getValue(kAXFocusedWindowAttribute) else { return nil }
        // Skip sheets / dialogs that misbehave when resized.
        if let role: String = win.getValue(kAXSubroleAttribute), role == "AXSheet" {
            return nil
        }
        return FocusedWindow(element: win, pid: pid)
    }

    var frame: CGRect {
        let p: CGPoint = element.getValue(kAXPositionAttribute) ?? .zero
        let s: CGSize = element.getValue(kAXSizeAttribute) ?? .zero
        return CGRect(origin: p, size: s)
    }

    /// Set the window frame. We toggle off enhanced UI on the owning app to avoid
    /// resize jank in apps that animate frame changes (e.g., some Electron, Office).
    func setFrame(_ rect: CGRect) {
        let appEl = AXUIElementCreateApplication(pid)
        let prevEnhanced: Bool = appEl.getValue("AXEnhancedUserInterface") ?? false
        if prevEnhanced { appEl.setValue("AXEnhancedUserInterface", false) }

        // When moving across screens, set size first so the new origin is interpreted
        // on the destination screen scale.
        element.setValue(kAXSizeAttribute, rect.size)
        element.setValue(kAXPositionAttribute, rect.origin)
        element.setValue(kAXSizeAttribute, rect.size)

        if prevEnhanced { appEl.setValue("AXEnhancedUserInterface", true) }
    }
}
