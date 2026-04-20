//  WindowAction.swift
//  Defines the model for window-positioning actions and a built-in catalog
//  of presets keyed off arrow keys / space / return.

import AppKit
import CoreGraphics

/// A relative rectangle, expressed as multipliers of the target screen's
/// visible frame. (0,0,1,1) = full screen; (0,0,0.5,1) = left half.
struct FrameSpec: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    func apply(to screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.origin.x + screenFrame.width * x,
            y: screenFrame.origin.y + screenFrame.height * y,
            width: screenFrame.width * w,
            height: screenFrame.height * h
        )
    }

    static let maximize = FrameSpec(x: 0, y: 0, w: 1, h: 1)

    // Halves
    static let leftHalf   = FrameSpec(x: 0,   y: 0,   w: 0.5, h: 1)
    static let rightHalf  = FrameSpec(x: 0.5, y: 0,   w: 0.5, h: 1)
    static let topHalf    = FrameSpec(x: 0,   y: 0,   w: 1,   h: 0.5)
    static let bottomHalf = FrameSpec(x: 0,   y: 0.5, w: 1,   h: 0.5)

    // Thirds (horizontal)
    static let leftThird       = FrameSpec(x: 0,         y: 0, w: 1.0/3.0, h: 1)
    static let leftTwoThirds   = FrameSpec(x: 0,         y: 0, w: 2.0/3.0, h: 1)
    static let rightThird      = FrameSpec(x: 2.0/3.0,   y: 0, w: 1.0/3.0, h: 1)
    static let rightTwoThirds  = FrameSpec(x: 1.0/3.0,   y: 0, w: 2.0/3.0, h: 1)

    // Thirds (vertical)
    static let topThird        = FrameSpec(x: 0, y: 0,         w: 1, h: 1.0/3.0)
    static let topTwoThirds    = FrameSpec(x: 0, y: 0,         w: 1, h: 2.0/3.0)
    static let bottomThird     = FrameSpec(x: 0, y: 2.0/3.0,   w: 1, h: 1.0/3.0)
    static let bottomTwoThirds = FrameSpec(x: 0, y: 1.0/3.0,   w: 1, h: 2.0/3.0)

    // Quarters
    static let qTL = FrameSpec(x: 0,   y: 0,   w: 0.5, h: 0.5)
    static let qTR = FrameSpec(x: 0.5, y: 0,   w: 0.5, h: 0.5)
    static let qBL = FrameSpec(x: 0,   y: 0.5, w: 0.5, h: 0.5)
    static let qBR = FrameSpec(x: 0.5, y: 0.5, w: 0.5, h: 0.5)
}

/// What an action does. `cycle` rotates through specs on repeated press.
/// `center` keeps the current size and centers on the target screen.
enum ActionKind: Codable, Equatable {
    case frame(FrameSpec)
    case cycle([FrameSpec])
    case center
}

/// A user-bindable action with a name + the action body.
struct WindowAction: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var kind: ActionKind
}
