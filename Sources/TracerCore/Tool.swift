public enum Tool: Int, CaseIterable, Codable, Sendable {
    case pen = 1, highlighter, arrow, rectangle, spotlight, text, redact

    public var displayName: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .spotlight: "Spotlight"
        case .text: "Text"
        case .redact: "Redact"
        }
    }

    // In dock order; the fifth slot is Spotlight live and Redact while capturing.
    public static func tools(for mode: AppMode) -> [Tool] {
        [.pen, .highlighter, .arrow, .rectangle, mode == .capturing ? .redact : .spotlight, .text]
    }

    public static func forDigit(_ d: Int, mode: AppMode) -> Tool? {
        let list = tools(for: mode)
        return list.indices.contains(d - 1) ? list[d - 1] : nil
    }

    public func isAvailable(in mode: AppMode) -> Bool { Tool.tools(for: mode).contains(self) }
}

public func pointerLabel(tool: Tool, fadeDelay: Double, shiftHeld: Bool) -> String {
    if tool == .spotlight { return tool.displayName }
    if shiftHeld { return "\(tool.displayName) · stays" }
    let n = fadeDelay.rounded() == fadeDelay ? String(Int(fadeDelay)) : String(fadeDelay)
    return "\(tool.displayName) · fades \(n)s"
}
