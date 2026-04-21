//  PreviewOverlay.swift
//  Borderless, non-activating panel that fills the target screen and draws
//  a translucent rounded rectangle at the target window frame. The hosted
//  SwiftUI view is reused across show() calls so frame changes animate
//  smoothly between targets (instead of snapping).

import AppKit
import SwiftUI

@MainActor
final class PreviewViewModel: ObservableObject {
    /// Rect in AppKit coordinates, relative to the panel's content view (top-left origin within the SwiftUI ZStack).
    @Published private(set) var computedFrame: CGRect = .zero
    @Published private(set) var containerSize: CGSize = .zero
    @Published private(set) var isShown: Bool = false

    func setIsShown(_ newState: Bool) {
        withAnimation(.smooth(duration: 0.2)) {
            isShown = newState
        }
    }

    /// Update the target rect. If the view is currently hidden, we seed the
    /// starting frame (centered, zero-size) without animation so the first
    /// reveal grows out from the target's center instead of sliding from (0,0).
    func update(localRect: CGRect, containerSize: CGSize, isScreenSwitch: Bool) {
        let wasHidden = !isShown

        if isScreenSwitch {
            // Jump without animating across screens.
            self.containerSize = containerSize
            self.computedFrame = localRect
            self.isShown = true
            return
        }

        if wasHidden {
            // Seed: start as a zero-size rect at the target's center, no animation.
            self.containerSize = containerSize
            self.computedFrame = CGRect(
                x: localRect.midX, y: localRect.midY, width: 0, height: 0
            )
        }

        withAnimation(.smooth(duration: 0.25)) {
            self.containerSize = containerSize
            self.computedFrame = localRect
            self.isShown = true
        }
    }
}

@MainActor
final class PreviewOverlay {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<PreviewContentView>?
    private let viewModel = PreviewViewModel()
    private var currentScreen: NSScreen?
    private var hideWorkItem: DispatchWorkItem?

    func show(targetFrameAX: CGRect, on screen: NSScreen) {
        // Preview is always on.

        // Cancel any pending teardown — we're showing again.
        hideWorkItem?.cancel()
        hideWorkItem = nil

        let screenFrame = screen.frame
        let isScreenSwitch: Bool

        if panel == nil {
            let p = NSPanel(contentRect: screenFrame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
            p.isFloatingPanel = true
            p.level = .screenSaver
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

            let host = NSHostingView(rootView: PreviewContentView(viewModel: viewModel))
            host.frame = CGRect(origin: .zero, size: screenFrame.size)
            host.autoresizingMask = [.width, .height]
            p.contentView = host
            self.hostingView = host
            self.panel = p
            isScreenSwitch = false
        } else {
            isScreenSwitch = (currentScreen != screen)
            if isScreenSwitch {
                panel?.setFrame(screenFrame, display: false)
            }
        }

        currentScreen = screen
        guard let panel else { return }

        // Convert AX rect to AppKit rect relative to this screen's origin.
        let appKitRect = NSScreen.axToAppKit(targetFrameAX)
        let localRect = CGRect(
            x: appKitRect.origin.x - screenFrame.origin.x,
            y: appKitRect.origin.y - screenFrame.origin.y,
            width: appKitRect.width, height: appKitRect.height
        )

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        viewModel.update(localRect: localRect, containerSize: screenFrame.size, isScreenSwitch: isScreenSwitch)
    }

    func hide() {
        guard let panel else { return }
        viewModel.setIsShown(false)

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Only tear down if we're still in the hidden state (not re-shown in the meantime).
            if self.viewModel.isShown == false {
                panel.orderOut(nil)
                self.panel = nil
                self.hostingView = nil
                self.currentScreen = nil
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

struct PreviewContentView: View {
    @ObservedObject var viewModel: PreviewViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 2)
                )
                .frame(width: viewModel.computedFrame.width,
                       height: viewModel.computedFrame.height)
                .offset(
                    x: viewModel.computedFrame.origin.x,
                    y: viewModel.containerSize.height
                        - viewModel.computedFrame.origin.y
                        - viewModel.computedFrame.height
                )
                .opacity(viewModel.isShown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
