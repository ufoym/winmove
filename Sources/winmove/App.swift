//  App.swift
//  Menu bar app entry point: sets up accessibility, hotkey monitor, and the
//  Settings window.

import AppKit
import SwiftUI

@main
struct WinmoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Button("Settings…") { delegate.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("About WinMove") { delegate.showAbout() }
            Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            if let img = Self.menuBarImage {
                Image(nsImage: img)
            } else {
                Image(systemName: "rectangle.3.group")
            }
        }
    }

    /// Loads the bundled menu-bar icon as a template image (so it renders
    /// correctly in both light and dark menu bars).
    private static let menuBarImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 15, height: 15)
        return img
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = HotKeyMonitor()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no dock icon.
        NSApp.setActivationPolicy(.accessory)

        Permissions.waitForAccessibility { [weak self] in
            guard let self else { return }
            self.monitor.delegate = WindowMover.shared
            if !self.monitor.start() {
                self.presentTapStartError()
            }
        }

        showSettings()
    }

    func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingView(rootView: SettingsView())
            hosting.translatesAutoresizingMaskIntoConstraints = false

            let ve = NSVisualEffectView()
            ve.material = .underWindowBackground
            ve.blendingMode = .behindWindow
            ve.state = .active
            ve.translatesAutoresizingMaskIntoConstraints = false

            let container = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 600))
            container.addSubview(ve)
            container.addSubview(hosting)
            NSLayoutConstraint.activate([
                ve.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                ve.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                ve.topAnchor.constraint(equalTo: container.topAnchor),
                ve.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: container.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            let win = NSWindow(
                contentRect: container.frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            win.contentView = container
            win.title = "WinMove"
            win.isReleasedWhenClosed = false
            win.titlebarAppearsTransparent = true
            win.isOpaque = false
            win.backgroundColor = .clear
            win.contentMinSize = NSSize(width: 560, height: 240)
            settingsWindow = win

            // Size the window to fit the SwiftUI content, capped at 80% of the
            // current screen height. Layout once so the hosting view reports a
            // real fitting size.
            container.layoutSubtreeIfNeeded()
            let fitting = hosting.fittingSize
            let screenH = (win.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
            let targetH = min(fitting.height, screenH * 0.8)
            let targetW = max(fitting.width, 560)
            win.setContentSize(NSSize(width: targetW, height: targetH))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        // Use the standard About panel — Apple HIG recommends this over a
        // custom alert. Populate it with the tagline and a clickable
        // homepage link. The panel reads app name, version, icon, and
        // copyright from Info.plist automatically.
        let tagline = "A small macOS window mover."
        let linkURL = URL(string: "http://ufoym.com/winmove")!

        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: tagline + "\n",
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            ]
        ))
        credits.append(NSAttributedString(
            string: linkURL.absoluteString,
            attributes: [
                .link: linkURL,
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            ]
        ))
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        credits.addAttribute(.paragraphStyle,
                             value: para,
                             range: NSRange(location: 0, length: credits.length))

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "WinMove",
        ])
    }

    private func presentTapStartError() {
        let a = NSAlert()
        a.messageText = "Could not start keyboard listener"
        a.informativeText = "winmove needs Accessibility permission to observe hotkeys. Open System Settings → Privacy & Security → Accessibility and enable winmove."
        a.runModal()
    }
}
