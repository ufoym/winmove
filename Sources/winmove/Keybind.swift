//  Keybind.swift
//  Trigger-key + action-key model. Uses CGKeyCode (hardware) for the action
//  so it is layout-independent and CGEventFlags for the modifier mask.

import AppKit
import CoreGraphics

/// The modifier flags that must be held to *arm* winmove. Default = ⌃⌥⌘ (Ctrl+Opt+Cmd).
struct TriggerKey: Codable, Equatable {
    var control: Bool = true
    var option: Bool = true
    var command: Bool = true
    var shift: Bool = false   // Shift is reserved for "cycle backwards"

    var flagMask: CGEventFlags {
        var f: CGEventFlags = []
        if control { f.insert(.maskControl) }
        if option  { f.insert(.maskAlternate) }
        if command { f.insert(.maskCommand) }
        if shift   { f.insert(.maskShift) }
        return f
    }

    /// Returns true iff `flags` contains every flag we require (shift is optional
    /// regardless of setting — the tap layer decides how to use shift).
    func matches(_ flags: CGEventFlags) -> Bool {
        if control && !flags.contains(.maskControl) { return false }
        if option  && !flags.contains(.maskAlternate) { return false }
        if command && !flags.contains(.maskCommand) { return false }
        return true
    }

    var description: String {
        var s = ""
        if control { s += "⌃" }
        if option  { s += "⌥" }
        if shift   { s += "⇧" }
        if command { s += "⌘" }
        return s
    }
}

/// A binding: an unordered set of non-modifier key codes → action.
struct Keybind: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var keys: Set<CGKeyCode>
    var action: WindowAction
}

// Key codes we actually care about for the defaults.
enum KC {
    static let ret:       CGKeyCode = 36   // Return
    static let tab:       CGKeyCode = 48
    static let space:     CGKeyCode = 49
    static let delete:    CGKeyCode = 51   // Backspace / Delete-left
    static let esc:       CGKeyCode = 53
    static let kpEnter:   CGKeyCode = 76   // Keypad Enter
    static let fwdDelete: CGKeyCode = 117  // Forward delete
    static let home:      CGKeyCode = 115
    static let pageUp:    CGKeyCode = 116
    static let end:       CGKeyCode = 119
    static let pageDown:  CGKeyCode = 121
    static let left:      CGKeyCode = 123
    static let right:     CGKeyCode = 124
    static let down:      CGKeyCode = 125
    static let up:        CGKeyCode = 126

    static func describe(_ code: CGKeyCode) -> String {
        // Symbol mapping follows the conventional macOS key glyphs
        // (see gist.github.com/jlyonsmith/6992156f18c423fd1c5af068aa311fb5).
        switch code {
        case ret:        return "↩"
        case tab:        return "⇥"
        case space:      return "␣"
        case delete:     return "⌫"
        case esc:        return "⎋"
        case kpEnter:    return "⌤"
        case fwdDelete:  return "⌦"
        case home:       return "↖"
        case pageUp:     return "⇞"
        case end:        return "↘"
        case pageDown:   return "⇟"
        case left:       return "←"
        case right:      return "→"
        case up:         return "↑"
        case down:       return "↓"
        default:
            if let s = fnKeyMap[code] { return s }
            if let s = letterMap[code] { return s }
            return "key\(code)"
        }
    }

    /// F1–F12 hardware codes → "F1"…"F12" labels.
    private static let fnKeyMap: [CGKeyCode: String] = [
        122: "F1",  120: "F2",   99: "F3",  118: "F4",
         96: "F5",   97: "F6",   98: "F7",  100: "F8",
        101: "F9",  109: "F10", 103: "F11", 111: "F12",
    ]

    // US-QWERTY hardware keycode → printable label. Layout-independent display
    // (we key bindings off the hardware code, not the current layout).
    private static let letterMap: [CGKeyCode: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
    ]
}
