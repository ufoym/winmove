//  AXHelpers.swift
//  Thin wrappers over the macOS Accessibility (AX) API for getting/setting
//  attributes on AXUIElements. Pattern borrowed from Loop.

import AppKit
import ApplicationServices

extension AXUIElement {
    static let systemWide = AXUIElementCreateSystemWide()

    func getValue<T>(_ attribute: String) -> T? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard err == .success, let v = value else { return nil }
        return Self.unpack(v) as? T
    }

    func setValue(_ attribute: String, _ value: Any) {
        AXUIElementSetAttributeValue(self, attribute as CFString, Self.pack(value))
    }

    func canSet(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success && settable.boolValue
    }

    func performAction(_ action: String) {
        AXUIElementPerformAction(self, action as CFString)
    }

    func getPID() -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(self, &pid)
        return pid
    }

    private static func pack(_ value: Any) -> AnyObject {
        switch value {
        case var p as CGPoint:
            return AXValueCreate(.cgPoint, &p)!
        case var s as CGSize:
            return AXValueCreate(.cgSize, &s)!
        case var r as CGRect:
            return AXValueCreate(.cgRect, &r)!
        case let b as Bool:
            return b as CFBoolean
        default:
            return value as AnyObject
        }
    }

    private static func unpack(_ value: AnyObject) -> Any {
        switch CFGetTypeID(value) {
        case AXValueGetTypeID():
            let v = value as! AXValue
            switch AXValueGetType(v) {
            case .cgPoint:
                var p = CGPoint.zero; AXValueGetValue(v, .cgPoint, &p); return p
            case .cgSize:
                var s = CGSize.zero; AXValueGetValue(v, .cgSize, &s); return s
            case .cgRect:
                var r = CGRect.zero; AXValueGetValue(v, .cgRect, &r); return r
            default:
                return value
            }
        default:
            return value
        }
    }
}
