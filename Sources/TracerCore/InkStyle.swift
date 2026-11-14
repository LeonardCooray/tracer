public struct RGBA: Codable, Equatable, Sendable {
    public var r, g, b, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255,
                  g: Double((hex >> 8) & 0xFF) / 255,
                  b: Double(hex & 0xFF) / 255,
                  a: alpha)
    }
}

public enum InkPalette {
    public static let presets: [RGBA] = [
        RGBA(hex: 0xFF453A), RGBA(hex: 0xFFD60A), RGBA(hex: 0x30D158),
        RGBA(hex: 0x0A84FF), RGBA(hex: 0xFFFFFF),
    ]
}

public struct StrokeStyle: Equatable, Sendable {
    public var color: RGBA
    public var width: Double

    public init(color: RGBA, width: Double) {
        self.color = color; self.width = width
    }
}

public func defaultWidth(for tool: Tool) -> Double {
    switch tool {
    case .pen, .arrow: 4
    case .highlighter: 18
    case .rectangle, .ellipse: 3.5
    case .text: 18
    case .spotlight, .redact: 0
    }
}

// Sizes [ and ] step through; nil for tools without a width. Text sizes are font points.
public func widthSteps(for tool: Tool) -> [Double]? {
    switch tool {
    case .pen, .arrow, .rectangle, .ellipse: [1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24]
    case .highlighter: [8, 12, 18, 24, 32, 40, 48]
    case .text: [10, 12, 14, 18, 24, 32, 40, 48, 64, 72]
    case .spotlight, .redact: nil
    }
}

public func clampWidth(_ w: Double, for tool: Tool) -> Double? {
    guard let steps = widthSteps(for: tool), w.isFinite, let lo = steps.first, let hi = steps.last else { return nil }
    return min(max(w, lo), hi)
}

// Off-ladder widths (the 3.5 pt rectangle, a context-menu pick) snap to the neighbouring step; past the end it stays put.
public func steppedWidth(_ w: Double, for tool: Tool, thicker: Bool) -> Double? {
    guard let steps = widthSteps(for: tool) else { return nil }
    return (thicker ? steps.first { $0 > w } : steps.last { $0 < w }) ?? w
}
