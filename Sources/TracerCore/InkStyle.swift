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
    case .rectangle: 3.5
    case .text: 18
    case .spotlight: 0
    }
}
