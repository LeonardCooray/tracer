public enum AppMode: Equatable, Sendable {
    case idle, drawing, capturing
}

public enum SessionEvent: Equatable, Sendable {
    case penHotkey, captureHotkey, escape, command(SessionCommand)
    case textEditingBegan, textEditingEnded, captureFinished
}

public enum SessionEffect: Equatable, Sendable {
    case showOverlays(interactive: Bool)
    case hideOverlays
    case clearInk
    case setFadeMode(FadeMode)
    case freezeScreens
    case registerSessionKeys(capture: Bool)
    case unregisterSessionKeys
    case selectTool(Tool)
    case undo
    case clearAll
    case copySelection
    case saveSelection
    case restorePreviousApp
}

public struct Session: Sendable {
    public private(set) var mode: AppMode = .idle
    public private(set) var tool: Tool = .pen
    public private(set) var isEditingText = false
    private var fadeDelay: Double

    public init(fadeDelay: Double = FadeSetting.defaultDelay) {
        self.fadeDelay = fadeDelay
    }

    public mutating func setFadeDelay(_ d: Double) { fadeDelay = FadeSetting.clamp(d) }

    public mutating func handle(_ e: SessionEvent) -> [SessionEffect] {
        switch (mode, e) {
        case (.idle, .penHotkey):
            mode = .drawing
            return [.showOverlays(interactive: true), .setFadeMode(.live(delay: fadeDelay)), .registerSessionKeys(capture: false)]
        case (.idle, .captureHotkey):
            mode = .capturing
            return [.freezeScreens, .showOverlays(interactive: true), .setFadeMode(.frozen), .registerSessionKeys(capture: true)]
                + fallBackFromSpotlight()
        case (.drawing, .captureHotkey):
            mode = .capturing
            isEditingText = false
            return [.freezeScreens, .setFadeMode(.frozen), .registerSessionKeys(capture: true)] + fallBackFromSpotlight()
        case (_, .escape) where isEditingText:
            isEditingText = false
            return []
        case (.drawing, .penHotkey), (.drawing, .escape), (.capturing, .escape), (.capturing, .captureFinished):
            return exit()
        case (.drawing, .textEditingBegan), (.capturing, .textEditingBegan):
            isEditingText = true
            return [.unregisterSessionKeys]
        case (.drawing, .textEditingEnded), (.capturing, .textEditingEnded):
            guard isEditingText else { return [] }
            isEditingText = false
            return [.registerSessionKeys(capture: mode == .capturing)]
        case (.drawing, .command(let c)), (.capturing, .command(let c)):
            return apply(c)
        default:
            return []
        }
    }

    private mutating func exit() -> [SessionEffect] {
        mode = .idle
        isEditingText = false
        return [.hideOverlays, .clearInk, .unregisterSessionKeys, .restorePreviousApp]
    }

    private mutating func fallBackFromSpotlight() -> [SessionEffect] {
        guard !tool.availableInCapture else { return [] }
        tool = .pen
        return [.selectTool(.pen)]
    }

    private mutating func apply(_ c: SessionCommand) -> [SessionEffect] {
        switch c {
        case .selectTool(let t):
            if mode == .capturing && !t.availableInCapture { return [] }
            tool = t
            return [.selectTool(t)]
        case .undo: return [.undo]
        case .clearAll: return [.clearAll]
        case .copy: return mode == .capturing ? [.copySelection] : []
        case .save: return mode == .capturing ? [.saveSelection] : []
        }
    }
}
