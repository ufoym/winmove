//  WindowMover.swift
//  The engine: receives a keybind firing, resolves the target screen (mouse-
//  based), computes the destination frame (advancing cycles when the same
//  action repeats), shows the preview, and commits the move.

import AppKit
import CoreGraphics

@MainActor
final class WindowMover: HotKeyMonitorDelegate {
    static let shared = WindowMover()
    private let overlay = PreviewOverlay()

    /// Remembers the last fired binding ID and its cycle index per-window (by pid+title hash).
    /// We key by binding ID alone — this is "good enough" for common usage, and matches
    /// Loop's behavior where cycle state is per-action, not per-window.
    private var cycleIndex: [UUID: Int] = [:]
    private var lastBindingID: UUID?

    // Pending move — staged while the trigger is held. Committed on disarm,
    // discarded on cancel. No window movement happens until release.
    private var pendingWindow: FocusedWindow?
    private var pendingFrame: CGRect?

    // HotKeyMonitorDelegate

    func hotKeyMonitorDidDisarm() {
        commitPending()
        overlay.hide()
        lastBindingID = nil
    }

    func hotKeyMonitorDidCancel() {
        // User cancelled (e.g. Escape) — drop the pending move without committing.
        pendingWindow = nil
        pendingFrame = nil
        overlay.hide()
        lastBindingID = nil
    }

    func hotKeyMonitorDidFire(_ binding: Keybind, shiftHeld: Bool) {
        guard let window = FocusedWindow.current() else { return }
        let screen = NSScreen.withMouse
        let screenFrame = screen.axVisibleFrame

        let targetAXFrame = resolveFrame(for: binding, screen: screenFrame, currentFrame: window.frame, shift: shiftHeld)

        let mouse = NSEvent.mouseLocation
        let backing = screen.backingScaleFactor
        let specStr: String
        switch binding.action.kind {
        case .frame(let s):
            specStr = String(format: "frame x=%.4f y=%.4f w=%.4f h=%.4f", s.x, s.y, s.w, s.h)
        case .cycle(let specs):
            let idx = cycleIndex[binding.id] ?? -1
            if specs.indices.contains(idx) {
                let s = specs[idx]
                specStr = String(format: "cycle[%d/%d] x=%.4f y=%.4f w=%.4f h=%.4f", idx, specs.count, s.x, s.y, s.w, s.h)
            } else {
                specStr = "cycle idx=\(idx) count=\(specs.count)"
            }
        case .center:
            specStr = "center"
        }
        Log.write("FIRE name=\"\(binding.action.name)\" \(specStr)")
        Log.write("  screen name=\"\(screen.localizedName)\" backing=\(backing) " +
                  "vf=\(fmt(screenFrame)) frame=\(fmt(screen.frame)) mouse=\(fmt(mouse))")
        Log.write("  windowBefore=\(fmt(window.frame)) target=\(fmt(targetAXFrame))")

        // Stage only — do not move the window yet.
        pendingWindow = window
        pendingFrame = targetAXFrame
        overlay.show(targetFrameAX: targetAXFrame, on: screen)
        lastBindingID = binding.id
    }

    private func commitPending() {
        if let w = pendingWindow, let f = pendingFrame {
            w.setFrame(f)
            // Read back what the application actually accepted (apps may clamp
            // to their own min size, snap, or refuse the move).
            let actual = w.frame
            let dw = actual.width  - f.width
            let dh = actual.height - f.height
            let dx = actual.origin.x - f.origin.x
            let dy = actual.origin.y - f.origin.y
            Log.write("  windowAfter=\(fmt(actual)) " +
                      String(format: "delta dx=%.1f dy=%.1f dw=%.1f dh=%.1f", dx, dy, dw, dh))
        }
        pendingWindow = nil
        pendingFrame = nil
    }

    private func fmt(_ r: CGRect) -> String {
        String(format: "(x=%.1f y=%.1f w=%.1f h=%.1f)", r.origin.x, r.origin.y, r.width, r.height)
    }

    private func fmt(_ p: CGPoint) -> String {
        String(format: "(x=%.1f y=%.1f)", p.x, p.y)
    }

    // MARK: - Frame resolution

    private func resolveFrame(for binding: Keybind, screen: CGRect, currentFrame: CGRect, shift: Bool) -> CGRect {
        switch binding.action.kind {
        case .frame(let spec):
            return spec.apply(to: screen)

        case .center:
            let size = CGSize(width: min(currentFrame.width, screen.width),
                              height: min(currentFrame.height, screen.height))
            return CGRect(
                x: screen.origin.x + (screen.width - size.width) / 2,
                y: screen.origin.y + (screen.height - size.height) / 2,
                width: size.width, height: size.height
            )

        case .cycle(let specs) where !specs.isEmpty:
            let idx = nextCycleIndex(for: binding, count: specs.count, shift: shift)
            return specs[idx].apply(to: screen)

        case .cycle:
            return screen   // empty cycle => fall back to full screen
        }
    }

    private func nextCycleIndex(for binding: Keybind, count: Int, shift: Bool) -> Int {
        let step = 1
        _ = shift

        // If we're firing the same binding again (while still armed), advance.
        // Otherwise reset to the first/last spec.
        let current = cycleIndex[binding.id]
        let next: Int
        if lastBindingID == binding.id, let current {
            next = ((current + step) % count + count) % count
        } else {
            next = 0
        }
        cycleIndex[binding.id] = next
        return next
    }
}
