//  HotKeyMonitor.swift
//  Global keyboard listener built on a CGEvent tap, following Loop's approach.
//
//  Model: user holds the TriggerKey (default ⌃⌥⌘). While held, any non-modifier
//  key we press is added to `pressedActionKeys`. When the pressed set matches
//  a binding, we fire it (and, for arrow keys, track repeat presses so that
//  cycle actions advance). The tap swallows matching keys so apps don't see them.
//
//  Requires Accessibility permission (CGEvent taps on keyboard events are gated
//  by TCC).

import AppKit
import Carbon.HIToolbox
import CoreGraphics

@MainActor
protocol HotKeyMonitorDelegate: AnyObject {
    /// Trigger released — commit any pending preview.
    func hotKeyMonitorDidDisarm()
    /// User cancelled (Escape) — discard any pending preview without committing.
    func hotKeyMonitorDidCancel()
    /// An action was fired. `shiftHeld` lets the engine cycle backwards.
    func hotKeyMonitorDidFire(_ binding: Keybind, shiftHeld: Bool)
}

final class HotKeyMonitor {
    weak var delegate: HotKeyMonitorDelegate?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var pressed: Set<CGKeyCode> = []
    private var armed: Bool = false

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - Tap callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if the system disabled us (timeout / user input).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let trigger = Settings.shared.triggerKey
        let matches = trigger.matches(flags)

        if type == .flagsChanged {
            if matches && !armed {
                armed = true
                pressed.removeAll()
            } else if !matches && armed {
                armed = false
                pressed.removeAll()
                DispatchQueue.main.async { [weak self] in self?.delegate?.hotKeyMonitorDidDisarm() }
            }
            // Don't consume modifier events.
            return Unmanaged.passUnretained(event)
        }

        guard armed else {
            return Unmanaged.passUnretained(event)
        }

        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let shift = flags.contains(.maskShift)

        if type == .keyDown {
            // Escape cancels the pending preview without committing.
            if code == KC.esc {
                DispatchQueue.main.async { [weak self] in self?.delegate?.hotKeyMonitorDidCancel() }
                pressed.removeAll()
                return nil
            }
            pressed.insert(code)
            // Find a binding whose keys == pressed set.
            if let bind = Settings.shared.keybinds.first(where: { $0.keys == pressed }) {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotKeyMonitorDidFire(bind, shiftHeld: shift)
                }
                // Swallow — app should not see this key.
                return nil
            }
            // Swallow known action keys (arrow/space/return) while armed so we
            // don't scroll the underlying app.
            if isActionKey(code) { return nil }
        } else if type == .keyUp {
            pressed.remove(code)
            if isActionKey(code) { return nil }
        }
        _ = isRepeat
        return Unmanaged.passUnretained(event)
    }

    private func isActionKey(_ c: CGKeyCode) -> Bool {
        c == KC.space || c == KC.ret || c == KC.left || c == KC.right || c == KC.up || c == KC.down
    }
}
