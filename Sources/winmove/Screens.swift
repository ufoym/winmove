//  Screens.swift
//  Screen helpers. AX uses top-left origin; AppKit uses bottom-left. Convert
//  carefully when computing target frames.

import AppKit

extension NSScreen {
    /// The screen the mouse cursor is currently on (or main screen as fallback).
    static var withMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// Visible frame (excluding menu bar / dock) in AX coordinates (top-left origin,
    /// where Y grows downward).
    var axVisibleFrame: CGRect {
        let global = NSScreen.screens[0].frame  // primary screen defines the global coord system
        let vf = visibleFrame
        return CGRect(
            x: vf.origin.x,
            y: global.height - vf.origin.y - vf.height,
            width: vf.width,
            height: vf.height
        )
    }

    /// Convert an AX (top-left) rect to AppKit (bottom-left) coords for overlay drawing.
    static func axToAppKit(_ rect: CGRect) -> CGRect {
        let global = NSScreen.screens[0].frame
        return CGRect(x: rect.origin.x, y: global.height - rect.origin.y - rect.height,
                      width: rect.width, height: rect.height)
    }
}
