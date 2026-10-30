public enum Tool: Int, CaseIterable, Codable, Sendable {
    case pen = 1, highlighter, arrow, rectangle, spotlight, text

    public var displayName: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .spotlight: "Spotlight"
        case .text: "Text"
        }
    }

    public static func forDigit(_ d: Int) -> Tool? { Tool(rawValue: d) }

    public var availableInCapture: Bool { self != .spotlight }
}

public func pointerLabel(tool: Tool, fadeDelay: Double, shiftHeld: Bool) -> String {
    if tool == .spotlight { return tool.displayName }
    if shiftHeld { return "\(tool.displayName) · stays" }
    let n = fadeDelay.rounded() == fadeDelay ? String(Int(fadeDelay)) : String(fadeDelay)
    return "\(tool.displayName) · fades \(n)s"
}
