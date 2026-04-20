//  SettingsView.swift
//  A minimal SwiftUI Settings window for editing the trigger, toggling
//  preview/backward-cycle, and managing keybinds (including custom frames).

import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @State private var showResetConfirm = false
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    private var hasCustomKeybinds: Bool {
        let presetNames = Set(Settings.defaultKeybinds().map { $0.action.name })
        return settings.keybinds.contains { !presetNames.contains($0.action.name) }
    }

    private func handleResetTapped() {
        if hasCustomKeybinds {
            showResetConfirm = true
        } else {
            settings.resetToDefaults()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Text("Launch at login")
                        Toggle("", isOn: $launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: launchAtLogin) { newValue in
                                LaunchAtLogin.isEnabled = newValue
                                let actual = LaunchAtLogin.isEnabled
                                if actual != newValue { launchAtLogin = actual }
                            }
                        Spacer()
                        RotatingHint(messages: [
                            "Hold the trigger and tap a key to move the focused window.",
                            "Click the trigger chips to change the global modifier combo.",
                            "Click any row's key chips to rebind its shortcut.",
                            "Click the left rectangle icon to set window size and position.",
                            "Click + on a row to turn it into a cycle of frames.",
                            "Cycle: tap the shortcut repeatedly to step through frames.",
                            "Use +/− at the bottom to add or remove custom keybinds."
                        ], interval: 5)
                    }
                    .padding(.leading, 3)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .fixedSize(horizontal: false, vertical: true)

            KeybindsSection(settings: settings, onResetRequested: handleResetTapped)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(minWidth: 560)
        .confirmationDialog(
            "Reset to defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset but keep custom keybinds") {
                settings.resetToDefaults(keepCustom: true)
            }
            Button("Reset and delete custom keybinds", role: .destructive) {
                settings.resetToDefaults(keepCustom: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore the built-in keybinds and the trigger to their defaults. Should your custom keybinds be kept?")
        }
    }
}

/// Rotates through a list of hint strings, swapping the visible one every
/// `interval` seconds with a crossfade. Secondary-colored, small text.
private struct RotatingHint: View {
    let messages: [String]
    let interval: TimeInterval
    @State private var index = 0

    var body: some View {
        Text(messages.isEmpty ? "" : messages[index])
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .id(index)
            .transition(.opacity)
            .onAppear { start() }
    }

    private func start() {
        guard messages.count > 1 else { return }
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                index = (index + 1) % messages.count
            }
        }
    }
}

/// A row that matches KeybindRow's visual layout but presents the global
/// trigger modifier combo at the top of the keybinds list.
private struct TriggerRow: View {
    @Binding var triggerKey: TriggerKey

    var body: some View {
        HStack(spacing: 10) {
            Text("Trigger")
                .lineLimit(1)
            Spacer(minLength: 12)
            TriggerRecorder(triggerKey: $triggerKey)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.08))
    }
}

/// Captures a modifier-key combination by listening to flagsChanged while
/// recording. The user holds the combo, then releases — release commits.
private struct TriggerRecorder: View {
    @Binding var triggerKey: TriggerKey
    @State private var recording = false
    @State private var captured: NSEvent.ModifierFlags = []
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            keysDisplay
                .frame(minHeight: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    if recording { stopRecording(commit: false) } else { startRecording() }
                }
        }
    }

    @ViewBuilder
    private var keysDisplay: some View {
        if recording {
            HStack(spacing: 3) {
                if captured.isEmpty {
                    Text("Press modifier keys…").foregroundStyle(.secondary).font(.system(size: 11))
                } else {
                    ForEach(symbols(captured), id: \.self) { KeyCap(text: $0) }
                    Text("(release to set)").foregroundStyle(.secondary).font(.system(size: 11))
                }
            }
        } else {
            let syms = symbols(triggerKeyModifiers)
            HStack(spacing: 3) {
                if syms.isEmpty {
                    Text("(click to record)").foregroundStyle(.secondary).font(.system(size: 11))
                } else {
                    ForEach(syms, id: \.self) { KeyCap(text: $0) }
                }
            }
        }
    }

    private func symbols(_ m: NSEvent.ModifierFlags) -> [String] {
        var arr: [String] = []
        if m.contains(.command) { arr.append("⌘") }
        if m.contains(.option)  { arr.append("⌥") }
        if m.contains(.control) { arr.append("⌃") }
        if m.contains(.shift)   { arr.append("⇧") }
        return arr
    }

    private var triggerKeyModifiers: NSEvent.ModifierFlags {
        var m: NSEvent.ModifierFlags = []
        if triggerKey.control { m.insert(.control) }
        if triggerKey.option  { m.insert(.option) }
        if triggerKey.command { m.insert(.command) }
        if triggerKey.shift   { m.insert(.shift) }
        return m
    }

    private func startRecording() {
        recording = true
        captured = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { ev in
            let mods = ev.modifierFlags.intersection([.control, .option, .command, .shift])
            if mods.isEmpty {
                // All keys released — commit the peak combination we saw.
                if !captured.isEmpty {
                    apply(captured)
                    stopRecording(commit: true)
                }
            } else {
                // Accumulate the peak set: as the user adds keys captured grows;
                // when they start releasing, we keep the largest combination
                // observed so we don't shrink down to whatever was released last.
                captured.formUnion(mods)
            }
            return nil
        }
    }

    private func stopRecording(commit: Bool) {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        recording = false
        if !commit { captured = [] }
    }

    private func apply(_ mods: NSEvent.ModifierFlags) {
        var t = triggerKey
        t.control = mods.contains(.control)
        t.option  = mods.contains(.option)
        t.command = mods.contains(.command)
        // Shift remains reserved for "cycle backwards".
        triggerKey = t
    }

    private func describe(_ m: NSEvent.ModifierFlags) -> String {
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option)  { s += "⌥" }
        if m.contains(.shift)   { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s
    }
}

private struct KeybindsSection: View {
    @ObservedObject var settings: Settings
    let onResetRequested: () -> Void
    @State private var editing: EditingTarget?
    @State private var expanded: Set<Keybind.ID> = []
    @State private var selection: Keybind.ID?

    /// Identifies which thing is being edited in the modal sheet:
    /// either a whole keybind, or a single frame step inside a cycle.
    private struct EditingTarget: Identifiable {
        enum Kind { case bind; case cycleStep(stepIndex: Int) }
        let id = UUID()
        let bindID: Keybind.ID
        var draft: Keybind          // working copy presented to the editor
        let kind: Kind
    }

    var body: some View {
        VStack(spacing: 0) {
            TriggerRow(triggerKey: $settings.triggerKey)
            Divider().opacity(0.35)
            ForEach(Array(settings.keybinds.enumerated()), id: \.element.id) { idx, bind in
                KeybindRow(
                    bind: bind,
                    modifiers: settings.triggerKey,
                    isExpanded: expanded.contains(bind.id),
                    isSelected: selection == bind.id,
                    onSelect: { selection = bind.id },
                    onToggleExpand: { toggleExpand(bind.id) },
                    onPromoteToCycle: { promoteToCycle(bindID: bind.id) },
                    onUpdateKeys: { newKeys in updateKeys(id: bind.id, keys: newKeys) },
                    onEdit: { editing = EditingTarget(bindID: bind.id, draft: bind, kind: .bind) },
                    onDelete: { deleteBind(id: bind.id) }
                )
                if isCycle(bind), expanded.contains(bind.id) {
                    CycleStepsList(
                        bind: bind,
                        onEditStep: { idx, stepDraft in
                            editing = EditingTarget(bindID: bind.id, draft: stepDraft, kind: .cycleStep(stepIndex: idx))
                        },
                        onDeleteStep: { idx in deleteCycleStep(bindID: bind.id, index: idx) },
                        onAddStep: { addCycleStep(bindID: bind.id) }
                    )
                }
                Divider().opacity(0.35)
            }
            ListFooterToolbar(
                canRemove: selection != nil,
                onAdd: addCustom,
                onRemove: removeSelected,
                onImport: importSettings,
                onExport: exportSettings,
                onReset: onResetRequested
            )
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .sheet(item: $editing) { target in
            KeybindEditor(binding: target.draft) { updated in
                applyEditorResult(target: target, updated: updated)
                editing = nil
            } onCancel: { editing = nil }
        }
    }

    private func isCycle(_ b: Keybind) -> Bool {
        if case .cycle = b.action.kind { return true }
        return false
    }

    private func toggleExpand(_ id: Keybind.ID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func updateKeys(id: Keybind.ID, keys: Set<CGKeyCode>) {
        guard let i = settings.keybinds.firstIndex(where: { $0.id == id }) else { return }
        settings.keybinds[i].keys = keys
    }

    private func removeSelected() {
        guard let id = selection else { return }
        settings.keybinds.removeAll { $0.id == id }
        expanded.remove(id)
        selection = nil
    }

    private func deleteBind(id: Keybind.ID) {
        settings.keybinds.removeAll { $0.id == id }
        expanded.remove(id)
        if selection == id { selection = nil }
    }

    private func exportSettings() {
        guard let data = settings.exportJSON() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "winmove-settings.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            if settings.importJSON(data) {
                expanded.removeAll()
                selection = nil
            } else {
                let alert = NSAlert()
                alert.messageText = "Import failed"
                alert.informativeText = "The selected file is not a valid winmove settings JSON."
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func addCustom() {
        let draft = Keybind(keys: [], action: WindowAction(name: "Custom",
            kind: .frame(FrameSpec(x: 0.1, y: 0.1, w: 0.8, h: 0.8))))
        editing = EditingTarget(bindID: draft.id, draft: draft, kind: .bind)
    }

    private func applyEditorResult(target: EditingTarget, updated: Keybind) {
        switch target.kind {
        case .bind:
            if let i = settings.keybinds.firstIndex(where: { $0.id == updated.id }) {
                settings.keybinds[i] = updated
            } else {
                settings.keybinds.append(updated)
            }
        case .cycleStep(let stepIndex):
            guard let i = settings.keybinds.firstIndex(where: { $0.id == target.bindID }) else { return }
            // Editor always saves as .frame — pull that spec back into the cycle.
            guard case .frame(let newSpec) = updated.action.kind else { return }
            guard case .cycle(var specs) = settings.keybinds[i].action.kind else { return }
            if specs.indices.contains(stepIndex) {
                specs[stepIndex] = newSpec
                settings.keybinds[i].action.kind = .cycle(specs)
            }
        }
    }

    private func deleteCycleStep(bindID: Keybind.ID, index: Int) {
        guard let i = settings.keybinds.firstIndex(where: { $0.id == bindID }) else { return }
        guard case .cycle(var specs) = settings.keybinds[i].action.kind else { return }
        guard specs.indices.contains(index) else { return }
        specs.remove(at: index)
        if specs.isEmpty {
            settings.keybinds.remove(at: i)
            expanded.remove(bindID)
        } else if specs.count == 1 {
            settings.keybinds[i].action.kind = .frame(specs[0])
            expanded.remove(bindID)
        } else {
            settings.keybinds[i].action.kind = .cycle(specs)
        }
    }

    private func addCycleStep(bindID: Keybind.ID) {
        guard let i = settings.keybinds.firstIndex(where: { $0.id == bindID }) else { return }
        guard case .cycle(var specs) = settings.keybinds[i].action.kind else { return }
        // Seed the new step from the last one so the editor opens on something sensible.
        let seed = specs.last ?? FrameSpec(x: 0.1, y: 0.1, w: 0.8, h: 0.8)
        specs.append(seed)
        settings.keybinds[i].action.kind = .cycle(specs)
    }

    /// Convert a non-cycle keybind into a cycle by appending a seed step.
    /// Called from the row-leading "+" on non-cycle rows.
    private func promoteToCycle(bindID: Keybind.ID) {
        guard let i = settings.keybinds.firstIndex(where: { $0.id == bindID }) else { return }
        let current = settings.keybinds[i].action.kind
        let firstSpec: FrameSpec
        switch current {
        case .frame(let s):  firstSpec = s
        case .center:        firstSpec = FrameSpec(x: 0.2, y: 0.2, w: 0.6, h: 0.6)
        case .cycle:         return    // already a cycle
        }
        let seed = FrameSpec(x: 0.1, y: 0.1, w: 0.8, h: 0.8)
        settings.keybinds[i].action.kind = .cycle([firstSpec, seed])
        expanded.insert(bindID)
    }
}

/// The expanded list of cycle steps shown beneath a cycle keybind row.
private struct CycleStepsList: View {
    let bind: Keybind
    let onEditStep: (Int, Keybind) -> Void
    let onDeleteStep: (Int) -> Void
    let onAddStep: () -> Void

    var body: some View {
        if case .cycle(let specs) = bind.action.kind {
            VStack(spacing: 0) {
                ForEach(Array(specs.enumerated()), id: \.offset) { idx, spec in
                    CycleStepRow(
                        index: idx,
                        spec: spec,
                        parentName: bind.action.name,
                        onEdit: {
                            // Hand the editor a synthetic single-frame keybind so it can reuse
                            // the existing FrameRectEditor flow; we'll splice the result back
                            // into the cycle in applyEditorResult.
                            let stepBind = Keybind(
                                id: bind.id,
                                keys: bind.keys,
                                action: WindowAction(id: bind.action.id,
                                                     name: "\(bind.action.name) · Step \(idx + 1)",
                                                     kind: .frame(spec))
                            )
                            onEditStep(idx, stepBind)
                        },
                        onDelete: { onDeleteStep(idx) }
                    )
                    Divider().opacity(0.2)
                }
                AddCycleStepRow(action: onAddStep)
            }
            .padding(.leading, 32)
            .background(Color.white.opacity(0.03))
        }
    }
}

private struct CycleStepRow: View {
    let index: Int
    let spec: FrameSpec
    let parentName: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                FramePreviewIcon(kind: .frame(spec))
                    .frame(width: 22, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to set window size and position")
            Text("Step \(index + 1)")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            Spacer(minLength: 12)
            Button(action: onDelete) {
                Image(systemName: "trash").font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete step")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

private struct AddCycleStepRow: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                Text("Add cycle step").font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Bottom toolbar under the keybind list: a plus (add custom) and minus
/// (remove current selection) button pair, Finder-sidebar style.
private struct ListFooterToolbar: View {
    let canRemove: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onImport: () -> Void
    let onExport: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            HStack(alignment: .center, spacing: 2) {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Add custom keybind")

                Button(action: onRemove) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(canRemove ? .secondary : Color.secondary.opacity(0.35))
                .disabled(!canRemove)
                .help("Remove selected keybind")

                Spacer()

                HStack(spacing: 12) {
                    Button("Import", action: onImport)
                        .help("Import settings from JSON")
                    Button("Export", action: onExport)
                        .help("Export settings to JSON")
                    Button("Reset", role: .destructive, action: onReset)
                }
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
        }
    }
}

/// A single row: action name on the left, keycap chips on the right.
/// Clicking the keycap area starts inline key recording (like TriggerRecorder).
/// Clicking elsewhere on the row selects it for removal via the footer toolbar.
private struct KeybindRow: View {
    let bind: Keybind
    let modifiers: TriggerKey
    let isExpanded: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleExpand: () -> Void
    let onPromoteToCycle: () -> Void
    let onUpdateKeys: (Set<CGKeyCode>) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var recording = false
    @State private var captured: Set<CGKeyCode> = []
    @State private var keyMonitor: Any?

    private var isCycle: Bool {
        if case .cycle = bind.action.kind { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            if isCycle {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Show cycle steps")
            } else {
                Button(action: onPromoteToCycle) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Add a cycle step")
            }
            Button(action: onEdit) {
                FramePreviewIcon(kind: bind.action.kind)
                    .frame(width: 22, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to set window size and position")
            Text(bind.action.name)
                .lineLimit(1)
            Spacer(minLength: 12)
            keysDisplay
                .frame(minHeight: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    if recording { stopRecording(commit: false) } else { startRecording() }
                }
            Button(action: onDelete) {
                Image(systemName: "trash").font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete keybind")
            .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(isSelected ? 0.25 : 0))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onDisappear { stopRecording(commit: false) }
    }

    @ViewBuilder
    private var keysDisplay: some View {
        if recording {
            HStack(spacing: 3) {
                if captured.isEmpty {
                    Text("Press keys…").foregroundStyle(.secondary).font(.system(size: 11))
                } else {
                    ForEach(captured.sorted(), id: \.self) { k in
                        KeyCap(text: KC.describe(k))
                    }
                    Text("(release to set)").foregroundStyle(.secondary).font(.system(size: 11))
                }
            }
        } else {
            HStack(spacing: 3) {
                ForEach(modifierSymbols, id: \.self) { sym in
                    KeyCap(text: sym)
                }
                let keys = bind.keys.sorted()
                if !keys.isEmpty {
                    Text("+").foregroundStyle(.secondary).font(.system(size: 11)).padding(.horizontal, 2)
                    ForEach(keys, id: \.self) { k in
                        KeyCap(text: KC.describe(k))
                    }
                } else if modifierSymbols.isEmpty {
                    Text("(click to record)").foregroundStyle(.secondary).font(.system(size: 11))
                }
            }
        }
    }

    private var modifierSymbols: [String] {
        var arr: [String] = []
        if modifiers.command { arr.append("⌘") }
        if modifiers.option  { arr.append("⌥") }
        if modifiers.control { arr.append("⌃") }
        if modifiers.shift   { arr.append("⇧") }
        return arr
    }

    private func startRecording() {
        recording = true
        captured = []
        var pressed: Set<CGKeyCode> = []
        var anyDown = false
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { ev in
            switch ev.type {
            case .keyDown:
                // Esc cancels recording without modifying the existing binding.
                if CGKeyCode(ev.keyCode) == KC.esc {
                    stopRecording(commit: false)
                    return nil
                }
                pressed.insert(CGKeyCode(ev.keyCode))
                captured = pressed
                anyDown = true
                return nil
            case .keyUp:
                if anyDown {
                    onUpdateKeys(pressed)
                    stopRecording(commit: true)
                }
                return nil
            default:
                return ev
            }
        }
    }

    private func stopRecording(commit: Bool) {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        recording = false
        if !commit { captured = [] }
    }
}

/// Mini-preview of where the window will land on the screen.
private struct FramePreviewIcon: View {
    let kind: ActionKind

    var body: some View {
        Canvas { ctx, size in
            let border: CGFloat = 1
            let screen = CGRect(x: border / 2,
                                y: border / 2,
                                width: size.width - border,
                                height: size.height - border)
            // Screen outline
            ctx.stroke(
                Path(roundedRect: screen, cornerRadius: 2),
                with: .color(.white.opacity(0.55)),
                lineWidth: border
            )
            // Target rect
            let spec: FrameSpec
            switch kind {
            case .frame(let s):            spec = s
            case .center:                  spec = FrameSpec(x: 0.2, y: 0.2, w: 0.6, h: 0.6)
            case .cycle(let specs):        spec = specs.first ?? .maximize
            }
            let inset: CGFloat = 1.5       // leave breathing room so fill stays inside the outline
            let inner = screen.insetBy(dx: inset, dy: inset)
            let rect = CGRect(
                x: inner.origin.x + inner.width * CGFloat(spec.x),
                y: inner.origin.y + inner.height * CGFloat(spec.y),
                width: max(1.5, inner.width * CGFloat(spec.w)),
                height: max(1.5, inner.height * CGFloat(spec.h))
            )
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 1.5),
                with: .color(.white.opacity(0.85))
            )
        }
    }
}

/// A single rounded keycap "pill". Used for both modifier symbols and action
/// keys; visually identical so the row reads as a uniform set of caps.
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .frame(minWidth: 22, minHeight: 24)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            )
    }
}

// MARK: - Binding editor

private struct KeybindEditor: View {
    @State var binding: Keybind
    let onSave: (Keybind) -> Void
    let onCancel: () -> Void

    // Working fields for frame kind
    @State private var x: Double = 0
    @State private var y: Double = 0
    @State private var w: Double = 1
    @State private var h: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Binding").font(.headline)
            TextField("Name", text: $binding.action.name)

            GroupBox("Frame") {
                VStack(spacing: 10) {
                    FrameRectEditor(x: $x, y: $y, w: $w, h: $h)
                        .frame(height: 220)
                    HStack(spacing: 16) {
                        PercentField(title: "x", value: $x, range: 0...(max(0, 1 - w)))
                        PercentField(title: "y", value: $y, range: 0...(max(0, 1 - h)))
                        PercentField(title: "w", value: $w, range: 0.05...(max(0.05, 1 - x)))
                        PercentField(title: "h", value: $h, range: 0.05...(max(0.05, 1 - y)))
                    }
                    Text("Drag the rectangle to move; drag its edges to resize, or type values directly. Values are percentages of the target screen's visible frame.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480)
        .onAppear { loadFromBinding() }
    }

    private func loadFromBinding() {
        switch binding.action.kind {
        case .frame(let s):
            x = snap(s.x); y = snap(s.y); w = snap(s.w); h = snap(s.h)
        case .center:
            // Legacy: convert to a centered default frame.
            x = 0.2; y = 0.2; w = 0.6; h = 0.6
        case .cycle(let specs):
            // Represent as custom first element; editor doesn't author cycles.
            if let first = specs.first {
                x = snap(first.x); y = snap(first.y); w = snap(first.w); h = snap(first.h)
            }
        }
    }

    /// Round to whole-percent precision so stored values match what the UI shows.
    private func snap(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    private func save() {
        var b = binding
        b.action.kind = .frame(FrameSpec(x: x, y: y, w: w, h: h))
        onSave(b)
    }
}

/// Editable "x: 25%" field. Values are stored as 0…1 doubles but the user
/// sees and types whole percent integers. Edits clamp to the supplied range.
private struct PercentField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("\(title):").foregroundStyle(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .monospacedDigit()
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { isFocused in
                    if !isFocused { commit() }
                }
            Text("%").foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .onAppear { text = format(value) }
        .onChange(of: value) { newValue in
            if !focused { text = format(newValue) }
        }
    }

    private func format(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))"
    }

    private func commit() {
        let parsed = Int(text.trimmingCharacters(in: .whitespaces)) ?? Int((value * 100).rounded())
        let clamped = min(max(Double(parsed) / 100.0, range.lowerBound), range.upperBound)
        // Snap to whole percent.
        value = (clamped * 100).rounded() / 100
        text = format(value)
    }
}

/// A draggable rectangle inside a screen-representing frame. The inner rect
/// can be moved by dragging its body and resized by dragging any of its four
/// edges. All values are normalized 0…1 of the outer screen.
private struct FrameRectEditor: View {
    @Binding var x: Double
    @Binding var y: Double
    @Binding var w: Double
    @Binding var h: Double

    private let edgeHit: CGFloat = 8        // hit slop around each edge
    private let minSize: Double = 0.05      // 5% min for w/h

    // Snapshot of the rect at gesture start so deltas are stable.
    @State private var dragStart: (x: Double, y: Double, w: Double, h: Double)?

    var body: some View {
        GeometryReader { geo in
            let outer = aspectFitScreen(in: geo.size)
            ZStack(alignment: .topLeading) {
                // Outer "screen" frame
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .frame(width: outer.width, height: outer.height)
                    .offset(x: outer.minX, y: outer.minY)

                // Inner "window" rect
                let r = innerRect(in: outer)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.accentColor.opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.95), lineWidth: 1.5)
                    )
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .gesture(moveGesture(outer: outer))

                // Edge handles (overlaid on top of body for resize)
                edgeHandle(.top,    rect: r).gesture(resizeGesture(.top, outer: outer))
                edgeHandle(.bottom, rect: r).gesture(resizeGesture(.bottom, outer: outer))
                edgeHandle(.leading,  rect: r).gesture(resizeGesture(.leading, outer: outer))
                edgeHandle(.trailing, rect: r).gesture(resizeGesture(.trailing, outer: outer))
            }
        }
    }

    // MARK: - Layout helpers

    private func aspectFitScreen(in size: CGSize) -> CGRect {
        // Use 16:10 as a generic screen ratio for the outer box.
        let ratio: CGFloat = 16.0 / 10.0
        var w = size.width
        var h = w / ratio
        if h > size.height {
            h = size.height
            w = h * ratio
        }
        let ox = (size.width - w) / 2
        let oy = (size.height - h) / 2
        return CGRect(x: ox, y: oy, width: w, height: h)
    }

    private func innerRect(in outer: CGRect) -> CGRect {
        CGRect(
            x: outer.minX + outer.width * CGFloat(x),
            y: outer.minY + outer.height * CGFloat(y),
            width:  max(1, outer.width  * CGFloat(w)),
            height: max(1, outer.height * CGFloat(h))
        )
    }

    // MARK: - Edge handles

    private enum Edge { case top, bottom, leading, trailing }

    private func edgeHandle(_ edge: Edge, rect r: CGRect) -> some View {
        let hit = edgeHit
        let frame: CGRect
        switch edge {
        case .top:
            frame = CGRect(x: r.minX, y: r.minY - hit/2, width: r.width, height: hit)
        case .bottom:
            frame = CGRect(x: r.minX, y: r.maxY - hit/2, width: r.width, height: hit)
        case .leading:
            frame = CGRect(x: r.minX - hit/2, y: r.minY, width: hit, height: r.height)
        case .trailing:
            frame = CGRect(x: r.maxX - hit/2, y: r.minY, width: hit, height: r.height)
        }
        let cursor: NSCursor = (edge == .top || edge == .bottom)
            ? .resizeUpDown : .resizeLeftRight
        return Color.white.opacity(0.001) // hit-testable but invisible
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .onHover { inside in
                if inside { cursor.push() } else { NSCursor.pop() }
            }
    }

    // MARK: - Gestures

    private func moveGesture(outer: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragStart == nil { dragStart = (x, y, w, h) }
                let dx = Double(g.translation.width  / outer.width)
                let dy = Double(g.translation.height / outer.height)
                let s = dragStart!
                x = snap(clamp(s.x + dx, 0, 1 - s.w))
                y = snap(clamp(s.y + dy, 0, 1 - s.h))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(_ edge: Edge, outer: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragStart == nil { dragStart = (x, y, w, h) }
                let s = dragStart!
                let dx = Double(g.translation.width  / outer.width)
                let dy = Double(g.translation.height / outer.height)
                switch edge {
                case .leading:
                    let newX = snap(clamp(s.x + dx, 0, s.x + s.w - minSize))
                    x = newX
                    w = snap(s.w + (s.x - newX))
                case .trailing:
                    w = snap(clamp(s.w + dx, minSize, 1 - s.x))
                case .top:
                    let newY = snap(clamp(s.y + dy, 0, s.y + s.h - minSize))
                    y = newY
                    h = snap(s.h + (s.y - newY))
                case .bottom:
                    h = snap(clamp(s.h + dy, minSize, 1 - s.y))
                }
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Round to whole-percent precision so dragging produces clean values.
    private func snap(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), max(lo, hi))
    }
}

// MARK: - Launch at login

/// Thin wrapper over SMAppService so the settings toggle can read/write
/// "start at login" state. Uses the modern API on macOS 13+.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        if SMAppService.mainApp.status != .enabled {
                            try SMAppService.mainApp.register()
                        }
                    } else {
                        if SMAppService.mainApp.status == .enabled {
                            try SMAppService.mainApp.unregister()
                        }
                    }
                } catch {
                    NSLog("LaunchAtLogin toggle failed: \(error)")
                }
            }
        }
    }
}
