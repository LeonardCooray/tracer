import AppKit
import ServiceManagement
import TracerCore

@MainActor
final class AppController: NSObject {
    private(set) var session = Session()
    private let hotkeys = HotkeyCenter()
    let overlays = OverlayManager()
    private let menuBar = MenuBarController()
    let dockState = DockState()
    lazy var dock = DockPanel(state: dockState)
    let text = TextEntryController()
    let output = OutputController()
    var capturer: ScreenCapturing = ScreenCapturer()
    var format: ImageFormat = .png
    var saveFolder = OutputController.defaultFolder
    let store: SettingsStore
    private(set) var settings: TracerSettings
    lazy var settingsModel = SettingsModel(settings: settings)
    lazy var settingsWindow = SettingsWindowController(model: settingsModel)
    private var ringTimer: Timer?
    private let defaults: UserDefaults
    private static let askedKey = "askedForScreenRecording"
    private var captureGeneration = 0
    private var awaitingFrames = false
    // Frame width is scaled by the backing factor so a HiDPI-only change still counts.
    private var screenLayout: [CGDirectDisplayID: CGRect] = [:]
    private var dockDisplay: CGDirectDisplayID?
    private(set) var lastSavedURL: URL?
    private(set) var frames: [CGDirectDisplayID: FrozenFrame] = [:]
    private var previousApp: NSRunningApplication?
    private var strokeOrder: [(view: InkView, id: UUID)] = []
    private(set) var tool: Tool = .pen
    private(set) var color = InkPalette.presets[0]
    private var width: Double?
    private var fadeDelay = FadeSetting.defaultDelay
    private(set) var hotkeyWarnings: [String] = []
    var loginService: LoginService = SystemLoginService()
    var presentAlert: @MainActor (_ title: String, _ body: String, _ offerSettings: Bool) -> Void = AppController.runAlert

    var sessionKeyCount: Int { hotkeys.sessionKeyCount }
    private(set) var sessionKeyWarnings: [String] = []

    #if DEBUG
    func resetScreenRecordingPrompt() { defaults.removeObject(forKey: Self.askedKey) }
    func markScreenRecordingPromptShown() { defaults.set(true, forKey: Self.askedKey) }
    #endif

    var globalHotkeysRegistered: Bool { hotkeys.isRegistered(id: HotkeyID.pen) && hotkeys.isRegistered(id: HotkeyID.capture) }

    private enum HotkeyID { static let pen: UInt32 = 1, capture: UInt32 = 2 }

    init(defaults: UserDefaults = .standard) {
        store = SettingsStore(defaults: defaults)
        self.defaults = defaults
        settings = store.load()
        super.init()
        overlays.configureView = { [weak self] ink, capture in self?.configure(ink, capture) }
        menuBar.onDraw = { [weak self] in self?.send(.penHotkey) }
        menuBar.onCapture = { [weak self] in self?.requestCapture() }
        menuBar.onSettings = { [weak self] in self?.settingsWindow.show() }
        settingsWindow.onShow = { [weak self] in self?.refreshLoginStatus() }
        settingsModel.onLoginToggle = { [weak self] in self?.setLaunchAtLogin($0) }
        settingsModel.onChange = { [weak self] in self?.update($0) }
        settingsModel.onRecording = { [weak self] recording in
            guard let self else { return }
            if recording { hotkeys.unregister(id: HotkeyID.pen); hotkeys.unregister(id: HotkeyID.capture) } else { registerHotkeys() }
        }
        dockState.onCommand = { [weak self] in self?.send(.command($0)) }
        dockState.onColor = { [weak self] in self?.setColor($0) }
        dockState.onWidth = { [weak self] in self?.setWidth($0) }
        dockState.onMoreColors = { [weak self] in self?.showColorPanel() }
        text.onBegan = { [weak self] in self?.send(.textEditingBegan) }
        text.onEnded = { [weak self] in self?.send(.textEditingEnded) }
        apply(settings, previous: nil)
        screenLayout = currentLayout
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    private var currentLayout: [CGDirectDisplayID: CGRect] {
        Dictionary(NSScreen.screens.compactMap { s in
            s.displayID.map { ($0, CGRect(origin: s.frame.origin, size: CGSize(width: s.frame.width * s.backingScaleFactor, height: s.frame.height))) }
        }, uniquingKeysWith: { a, _ in a })
    }

    // `force` lets the self-test simulate a change on a single-display Mac.
    func screensChanged(force: Bool = false) {
        let layout = currentLayout
        guard force || layout != screenLayout else { return }
        screenLayout = layout
        if session.mode == .drawing { text.commit() } else { text.cancel() }
        if session.mode == .capturing { send(.escape) }
        overlays.sync()
        let live = Set(overlays.inkViews.values.map(ObjectIdentifier.init))
        strokeOrder.removeAll { !live.contains(ObjectIdentifier($0.view)) }
        if session.mode == .drawing {
            enterLiveChrome(true)
            let screen = dockDisplay.flatMap { overlays.screen(of: $0) } ?? screenUnderPointer
            if let screen {
                dockDisplay = screen.displayID
                dock.slideIn(onRightEdgeOf: screen)
            }
        }
        updateIdleRing()
    }

    private func pointerMoved(in view: InkView) {
        guard session.mode == .drawing,
              let id = overlays.inkViews.first(where: { $0.value === view })?.key,
              id != dockDisplay, let screen = overlays.screen(of: id) else { return }
        dockDisplay = id
        dock.slideIn(onRightEdgeOf: screen)
    }

    func update(_ new: TracerSettings) {
        let old = settings
        settings = new.validated()
        store.save(settings)
        apply(settings, previous: old)
    }

    private func apply(_ s: TracerSettings, previous: TracerSettings?) {
        format = s.format
        saveFolder = s.saveFolder
        fadeDelay = s.fadeDelay
        session.setFadeDelay(s.fadeDelay)
        overlays.inkViews.values.forEach(applyStyle)
        if previous?.penHotkey != s.penHotkey || previous?.captureHotkey != s.captureHotkey || previous == nil { registerHotkeys() }
        settingsModel.settings = settings
        updateIdleRing()
    }

    // Acts on the user's click and macOS's real status, never on the stored copy.
    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try loginService.register() } else { try loginService.unregister() }
            settingsModel.loginError = nil
        } catch {
            settingsModel.loginError = "Couldn't change launch at login: \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    private func refreshLoginStatus() {
        let status = loginService.status
        settingsModel.loginStatus = status
        settings.launchAtLogin = status == .enabled || status == .requiresApproval
        store.save(settings)
        settingsModel.settings = settings
    }

    private func updateIdleRing() {
        let want = session.mode == .idle && settings.cursorRingAlwaysOn
        if want {
            overlays.show(interactive: false)
            for v in overlays.inkViews.values { v.showsCursorRing = true; v.showsPointerLabel = false }
            if ringTimer == nil {
                ringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.trackRing() }
                }
            }
        } else {
            ringTimer?.invalidate()
            ringTimer = nil
            if session.mode == .idle { overlays.hide() }
        }
    }

    private func trackRing() {
        let m = NSEvent.mouseLocation
        for (id, v) in overlays.inkViews {
            guard let f = overlays.screen(of: id)?.frame else { continue }
            let p = f.contains(m) ? NSPoint(x: m.x - f.minX, y: m.y - f.minY) : nil
            if p != v.pointer { v.setPointer(p) }
        }
    }

    private func configure(_ ink: InkView, _ capture: CaptureView) {
        ink.onStrokeEnded = { [weak self] v in
            if let id = v.model.strokes.last?.id { self?.strokeOrder.append((v, id)) }
        }
        ink.onPointerMoved = { [weak self] in self?.pointerMoved(in: $0) }
        ink.onTextClick = { [weak self] v, p in
            guard let self else { return }
            if text.isEditing { text.commit(); return }
            text.begin(at: p, in: v, style: currentStyle)
        }
        capture.onSelectionChanged = { [weak self] in self?.selectionChanged(in: $0) }
        capture.onPointerDown = { [weak self] in
            guard let self, text.isEditing else { return false }
            text.commit()
            return true
        }
        applyStyle(to: ink)
        switch session.mode {
        case .idle: break
        case .drawing: ink.model.mode = .live(delay: fadeDelay)
        case .capturing: ink.model.mode = .frozen
        }
    }

    private func registerHotkeys() {
        var warnings: [String] = []
        let pen = settings.penHotkey, cap = settings.captureHotkey
        if !hotkeys.register(pen, id: HotkeyID.pen, exclusive: true, handler: { [weak self] in self?.send(.penHotkey) }) {
            warnings.append("Draw hotkey \(pen.displayString) couldn't be registered (another app may be using it)")
        }
        if !hotkeys.register(cap, id: HotkeyID.capture, exclusive: true, handler: { [weak self] in self?.requestCapture() }) {
            warnings.append("Capture hotkey \(cap.displayString) couldn't be registered (another app may be using it)")
        }
        hotkeyWarnings = warnings
        menuBar.setWarnings(warnings + sessionKeyWarnings)
        settingsModel.warnings = warnings
        menuBar.setShortcuts(draw: pen.displayString, capture: cap.displayString)
    }

    func send(_ event: SessionEvent) {
        for effect in session.handle(event) { perform(effect) }
        dockState.tool = session.tool
        dockState.mode = session.mode
        updateIdleRing()
    }

    func requestCapture() {
        guard session.mode != .capturing else { return }
        if text.isEditing { text.commit() }
        guard capturer.hasPermission else {
            if session.mode == .drawing { send(.escape) }
            showPermissionAlert()
            return
        }
        send(.captureHotkey)
    }

    private func handleSessionKey(_ key: SessionKey) {
        if key == .escape { send(.escape); return }
        if let c = command(for: key, mode: session.mode, isEditingText: session.isEditingText) {
            send(.command(c))
        }
    }

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .showOverlays(let interactive):
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
            overlays.show(interactive: interactive)
            enterLiveChrome(session.mode == .drawing)
            if session.mode == .drawing, let screen = screenUnderPointer {
                dockDisplay = screen.displayID
                dock.slideIn(onRightEdgeOf: screen)
            }
        case .hideOverlays:
            captureGeneration += 1
            setAwaitingFrames(false)
            text.cancel()
            dock.slideOut()
            NSColorPanel.shared.orderOut(nil)
            overlays.inkViews.values.forEach { $0.showsCursorRing = false; $0.setPointer(nil) }
            overlays.captureViews.values.forEach { $0.reset() }
            overlays.frozenViews.values.forEach { $0.frame_ = nil }
            frames = [:]
            overlays.hide()
        case .clearInk, .clearAll:
            overlays.inkViews.values.forEach { $0.clear() }
            strokeOrder.removeAll()
        case .setFadeMode(let mode):
            if mode == .frozen { overlays.inkViews.values.forEach { $0.model.prune(at: InkView.now) } }
            overlays.inkViews.values.forEach { $0.model.mode = mode }
        case .freezeScreens:
            freeze()
        case .registerSessionKeys(let capture):
            let failed = hotkeys.registerSessionKeys(capture: capture) { [weak self] in self?.handleSessionKey($0) }
            sessionKeyWarnings = failed.isEmpty ? [] : ["Drawing keys unavailable: " + failed.map(\.label).joined(separator: ", ")]
            menuBar.setWarnings(hotkeyWarnings + sessionKeyWarnings)
        case .unregisterSessionKeys:
            hotkeys.unregisterSessionKeys()
        case .selectTool(let t):
            if text.isEditing { text.commit() }
            overlays.inkViews.values.forEach { $0.finishActiveStroke() }
            tool = t
            width = nil
            overlays.inkViews.values.forEach(applyStyle)
            if session.mode == .capturing { overlays.captureViews.values.forEach { $0.armed = true } }
        case .undo:
            // Entries for strokes that already faded away are skipped.
            while let (v, id) = strokeOrder.popLast() {
                if v.removeStroke(id: id) { break }
            }
        case .copySelection:
            guard let img = composedSelection() else { return }
            guard output.copy(img, format: format) else {
                presentAlert("Couldn't copy the screenshot", "The image couldn't be put on the clipboard. Try again or save it instead.", false)
                return
            }
            send(.captureFinished)
        case .saveSelection:
            guard let img = composedSelection() else { return }
            guard let url = output.save(img, format: format, folder: saveFolder) else {
                presentAlert("Couldn't save the screenshot",
                             "Neither \(saveFolder.path) nor \(output.fallbackFolder.path) can be written to. Choose another folder in Settings, or copy it instead.",
                             false)
                return
            }
            lastSavedURL = url
            send(.captureFinished)
        case .restorePreviousApp:
            previousApp?.activate()
            previousApp = nil
        }
    }

    // The overlay keeps catching clicks while frames load, so nothing reaches other apps; the views just ignore them.
    private func setAwaitingFrames(_ waiting: Bool) {
        awaitingFrames = waiting
        overlays.inkViews.values.forEach { $0.acceptsInput = !waiting }
        overlays.captureViews.values.forEach { $0.acceptsInput = !waiting }
    }

    private func enterLiveChrome(_ live: Bool) {
        for v in overlays.inkViews.values {
            v.showsCursorRing = live
            v.showsPointerLabel = live
            if !live { v.setPointer(nil) }
        }
        if !live { dock.orderOut(nil) }
    }

    private func freeze() {
        enterLiveChrome(false)
        captureGeneration += 1
        let generation = captureGeneration
        setAwaitingFrames(true)
        Task { @MainActor in
            do {
                let captured = try await capturer.captureAll()
                guard generation == captureGeneration, session.mode == .capturing else { return }
                setAwaitingFrames(false)
                frames = captured
                for (id, frame) in captured {
                    overlays.frozenViews[id]?.frame_ = frame
                    if let c = overlays.captureViews[id] {
                        c.scale = frame.scale
                        c.format = format
                        c.isHidden = false
                    }
                }
            } catch {
                guard generation == captureGeneration else { return }
                send(.escape)
                if capturer.hasPermission {
                    presentAlert("Couldn't capture the screen", error.localizedDescription, false)
                } else {
                    showPermissionAlert()
                }
            }
        }
    }

    private func selectionChanged(in view: CaptureView) {
        if view.selection != nil {
            for other in overlays.captureViews.values where other !== view && other.selection != nil { other.clearSelection() }
        }
        let active = overlays.captureViews.first { $0.value.selection != nil }
        dockState.canOutput = active != nil
        guard let (id, cv) = active, let sel = cv.selection, let screen = overlays.screen(of: id) else {
            dock.orderOut(nil)
            return
        }
        dockState.mode = .capturing
        let size = dock.fittingSize
        let local = dockOrigin(selection: sel, dockSize: size, screen: NSRect(origin: .zero, size: screen.frame.size))
        dock.place(at: NSPoint(x: screen.frame.minX + local.x, y: screen.frame.minY + local.y))
    }

    private func composedSelection() -> CGImage? {
        guard let (id, cv) = overlays.captureViews.first(where: { $0.value.selection != nil }),
              let sel = cv.selection, let frame = frames[id], let ink = overlays.inkViews[id] else { return nil }
        return Compositor.image(base: frame.image, baseScale: frame.scale, strokes: ink.model.strokes, selection: sel)
    }

    // The first time, only macOS's own prompt appears; Tracer's alert covers later attempts.
    private func showPermissionAlert() {
        if !defaults.bool(forKey: Self.askedKey) {
            defaults.set(true, forKey: Self.askedKey)
            capturer.requestPermission()
            return
        }
        presentAlert("Tracer needs Screen Recording permission to take screenshots",
                     "Turn on Tracer in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Tracer. Drawing works without it.",
                     true)
    }

    static func runAlert(title: String, body: String, offerSettings: Bool) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: offerSettings ? "Open System Settings" : "OK")
        if offerSettings { alert.addButton(withTitle: "Cancel") }
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, offerSettings,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private var screenUnderPointer: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    private var currentStyle: StrokeStyle { StrokeStyle(color: color, width: width ?? defaultWidth(for: tool)) }

    private func applyStyle(to view: InkView) {
        view.tool = tool
        view.style = currentStyle
        view.fadeDelay = fadeDelay
    }

    func setColor(_ c: RGBA) {
        color = c
        dockState.color = c
        overlays.inkViews.values.forEach(applyStyle)
    }

    private func setWidth(_ w: Double) {
        width = w
        overlays.inkViews.values.forEach(applyStyle)
    }

    private func showColorPanel() {
        let panel = NSColorPanel.shared
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        NSApp.activate()
        panel.orderFrontRegardless()
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        guard let c = sender.color.usingColorSpace(.sRGB) else { return }
        setColor(RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent))
    }
}

extension SessionKey {
    var label: String {
        switch self {
        case .digit(let n): "\(n)"
        case .escape: "Esc"
        case .delete: "Delete"
        case .undo: "⌘Z"
        case .returnKey: "Return"
        case .copy: "⌘C"
        case .save: "⌘S"
        }
    }
}

@MainActor
protocol LoginService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
struct SystemLoginService: LoginService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}
