//  Settings.swift
//  Persists trigger key + keybinds as JSON under UserDefaults. Keeps shape
//  simple enough to edit by hand if needed.

import AppKit
import Combine

final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var triggerKey: TriggerKey { didSet { save() } }
    @Published var keybinds: [Keybind] { didSet { save() } }

    private let defaults = UserDefaults.standard
    private static let key = "winmove.settings.v1"

    private struct Payload: Codable {
        var triggerKey: TriggerKey
        // Kept in the payload for backward-compatibility with older on-disk
        // settings; no longer user-configurable.
        var cycleBackwardsOnShift: Bool?
        var showPreview: Bool?
        var keybinds: [Keybind]
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let p = try? JSONDecoder().decode(Payload.self, from: data) {
            self.triggerKey = p.triggerKey
            self.keybinds = p.keybinds
        } else {
            self.triggerKey = TriggerKey()
            self.keybinds = Self.defaultKeybinds()
        }
    }

    private func save() {
        let p = Payload(triggerKey: triggerKey,
                        cycleBackwardsOnShift: nil,
                        showPreview: nil,
                        keybinds: keybinds)
        if let data = try? JSONEncoder().encode(p) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Encode current settings to pretty-printed JSON for export.
    func exportJSON() -> Data? {
        let p = Payload(triggerKey: triggerKey,
                        cycleBackwardsOnShift: nil,
                        showPreview: nil,
                        keybinds: keybinds)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(p)
    }

    /// Replace current settings from a JSON payload. Returns true on success.
    @discardableResult
    func importJSON(_ data: Data) -> Bool {
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else {
            return false
        }
        triggerKey = p.triggerKey
        keybinds = p.keybinds
        return true
    }

    func resetToDefaults(keepCustom: Bool = false) {
        triggerKey = TriggerKey()
        if keepCustom {
            let presetNames = Set(Self.defaultKeybinds().map { $0.action.name })
            let customs = keybinds.filter { !presetNames.contains($0.action.name) }
            keybinds = Self.defaultKeybinds() + customs
        } else {
            keybinds = Self.defaultKeybinds()
        }
    }

    // MARK: - Built-in defaults

    static func defaultKeybinds() -> [Keybind] {
        [
            Keybind(keys: [KC.space],
                    action: WindowAction(name: "Maximize", kind: .frame(.maximize))),
            Keybind(keys: [KC.ret],
                    action: WindowAction(name: "Center", kind: .center)),

            // Arrow halves -> cycle through 1/2 · 1/3 · 2/3
            Keybind(keys: [KC.left],
                    action: WindowAction(name: "Left",
                        kind: .cycle([.leftHalf, .leftThird, .leftTwoThirds]))),
            Keybind(keys: [KC.right],
                    action: WindowAction(name: "Right",
                        kind: .cycle([.rightHalf, .rightThird, .rightTwoThirds]))),
            Keybind(keys: [KC.up],
                    action: WindowAction(name: "Top",
                        kind: .cycle([.topHalf, .topThird, .topTwoThirds]))),
            Keybind(keys: [KC.down],
                    action: WindowAction(name: "Bottom",
                        kind: .cycle([.bottomHalf, .bottomThird, .bottomTwoThirds]))),

            // Quarters via arrow combos
            Keybind(keys: [KC.up, KC.left],
                    action: WindowAction(name: "Top-Left Quarter",    kind: .frame(.qTL))),
            Keybind(keys: [KC.up, KC.right],
                    action: WindowAction(name: "Top-Right Quarter",   kind: .frame(.qTR))),
            Keybind(keys: [KC.down, KC.left],
                    action: WindowAction(name: "Bottom-Left Quarter", kind: .frame(.qBL))),
            Keybind(keys: [KC.down, KC.right],
                    action: WindowAction(name: "Bottom-Right Quarter",kind: .frame(.qBR))),
        ]
    }
}
