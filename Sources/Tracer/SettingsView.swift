import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import TracerCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: TracerSettings
    @Published var warnings: [String] = []
    @Published var loginError: String?
    @Published var loginStatus = SMAppService.mainApp.status
    var onChange: (TracerSettings) -> Void = { _ in }
    var onRecording: (Bool) -> Void = { _ in }
    var onLoginToggle: (Bool) -> Void = { _ in }

    init(settings: TracerSettings) { self.settings = settings }

    func update(_ change: (inout TracerSettings) -> Void) {
        var s = settings
        change(&s)
        onChange(s)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Hotkeys") {
                LabeledContent("Draw on screen") {
                    HotkeyRecorder(hotkey: model.settings.penHotkey, other: model.settings.captureHotkey, otherName: "Capture",
                                   onRecording: model.onRecording) { k in
                        model.update { $0.penHotkey = k }
                    }
                }
                LabeledContent("Capture region") {
                    HotkeyRecorder(hotkey: model.settings.captureHotkey, other: model.settings.penHotkey, otherName: "Draw",
                                   onRecording: model.onRecording) { k in
                        model.update { $0.captureHotkey = k }
                    }
                }
                ForEach(model.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }
            }
            Section("Drawing") {
                LabeledContent("Ink fades after") {
                    HStack {
                        Slider(value: Binding(get: { model.settings.fadeDelay },
                                              set: { v in model.update { $0.fadeDelay = v.rounded() } }),
                               in: FadeSetting.range, step: 1)
                            .frame(width: 180)
                        Text("\(Int(model.settings.fadeDelay)) s").monospacedDigit().frame(width: 34, alignment: .trailing)
                    }
                }
                Toggle("Show cursor ring when not drawing", isOn: Binding(
                    get: { model.settings.cursorRingAlwaysOn }, set: { v in model.update { $0.cursorRingAlwaysOn = v } }))
            }
            Section("Screenshots") {
                LabeledContent("Save to") {
                    HStack {
                        Text(model.settings.saveFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle).frame(maxWidth: 200, alignment: .trailing)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Picker("Format", selection: Binding(get: { model.settings.format },
                                                    set: { v in model.update { $0.format = v } })) {
                    Text("PNG").tag(ImageFormat.png)
                    Text("JPEG").tag(ImageFormat.jpeg)
                }
                .pickerStyle(.segmented)
                Text("Always full Retina resolution at the highest quality.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                    set: { v in model.onLoginToggle(v) }))
                if model.loginStatus == .requiresApproval {
                    Text("Approve Tracer in System Settings → General → Login Items.").font(.callout).foregroundStyle(.orange)
                }
                if let e = model.loginError {
                    Text(e).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.settings.saveFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { model.update { $0.saveFolder = url } }
    }
}

extension Notification.Name {
    static let tracerStopRecording = Notification.Name("TracerStopRecording")
}

@MainActor
final class RecorderState: ObservableObject {
    @Published var recording = false
    @Published var problem: String?
    var monitor: Any?
    private var observer: Any?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .tracerStopRecording, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    func cancel() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
        problem = nil
    }
}

// Uses an ObservableObject rather than @State: the Command Line Tools build can't load the SwiftUI macro plugin.
struct HotkeyRecorder: View {
    let hotkey: Hotkey
    let other: Hotkey
    let otherName: String
    let onRecording: (Bool) -> Void
    let onSet: (Hotkey) -> Void
    @StateObject private var state = RecorderState()

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button(state.recording ? "Press keys…" : hotkey.displayString) { state.recording ? stop() : start() }
                .frame(minWidth: 110)
            if let problem = state.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
        }
    }

    private func start() {
        state.recording = true
        state.problem = nil
        onRecording(true)
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let k = Hotkey(keyCode: UInt32(e.keyCode), modifiers: carbonModifiers(e.modifierFlags))
            if let problem = hotkeyProblem(k, other: other, otherName: otherName) {
                state.problem = problem
            } else {
                onSet(k)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let m = state.monitor { NSEvent.removeMonitor(m) }
        state.monitor = nil
        state.recording = false
        onRecording(false)
    }

    private func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.command) { m |= Hotkey.command }
        if f.contains(.shift) { m |= Hotkey.shift }
        if f.contains(.option) { m |= Hotkey.option }
        if f.contains(.control) { m |= Hotkey.control }
        return m
    }
}

@MainActor
final class SettingsWindowController {
    let model: SettingsModel
    private(set) var window: NSWindow?

    var onShow: () -> Void = {}

    init(model: SettingsModel) { self.model = model }

    func stopRecording() {
        NotificationCenter.default.post(name: .tracerStopRecording, object: nil)
        model.onRecording(false)
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Tracer Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
                NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stopRecording() }
                }
            }
            window = w
        }
        onShow()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
