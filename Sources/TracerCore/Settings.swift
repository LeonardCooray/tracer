import Foundation

public struct TracerSettings: Codable, Equatable, Sendable {
    public var penHotkey: Hotkey
    public var captureHotkey: Hotkey
    public var fadeDelay: Double
    public var saveFolder: URL
    public var format: ImageFormat
    public var launchAtLogin: Bool
    public var cursorRingAlwaysOn: Bool
    public var strokeWidths = StrokeWidths()

    public static let defaults = TracerSettings(
        penHotkey: .defaultPen, captureHotkey: .defaultCapture, fadeDelay: FadeSetting.defaultDelay,
        saveFolder: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Tracer"),
        format: .png, launchAtLogin: false, cursorRingAlwaysOn: false)

    public func validated() -> TracerSettings {
        var s = self
        s.fadeDelay = FadeSetting.clamp(fadeDelay)
        s.strokeWidths = strokeWidths.validated()
        if !s.penHotkey.isUsableGlobally { s.penHotkey = .defaultPen }
        if !s.captureHotkey.isUsableGlobally { s.captureHotkey = .defaultCapture }
        if s.penHotkey == s.captureHotkey {
            s.penHotkey = .defaultPen
            s.captureHotkey = .defaultCapture
        }
        return s
    }

    public func strokeWidth(for tool: Tool) -> Double { strokeWidths[tool] ?? defaultWidth(for: tool) }
}

// Prefs saved before a field existed still load, keeping everything else.
extension TracerSettings {
    private enum CodingKeys: String, CodingKey {
        case penHotkey, captureHotkey, fadeDelay, saveFolder, format, launchAtLogin, cursorRingAlwaysOn, strokeWidths
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(penHotkey: try c.decode(Hotkey.self, forKey: .penHotkey),
                  captureHotkey: try c.decode(Hotkey.self, forKey: .captureHotkey),
                  fadeDelay: try c.decode(Double.self, forKey: .fadeDelay),
                  saveFolder: try c.decode(URL.self, forKey: .saveFolder),
                  format: try c.decode(ImageFormat.self, forKey: .format),
                  launchAtLogin: try c.decode(Bool.self, forKey: .launchAtLogin),
                  cursorRingAlwaysOn: try c.decode(Bool.self, forKey: .cursorRingAlwaysOn),
                  strokeWidths: (try? c.decodeIfPresent(StrokeWidths.self, forKey: .strokeWidths)) ?? StrokeWidths())
    }
}

// Saved per tool by name, so the JSON reads {"pen": 6} and survives tool reordering.
public struct StrokeWidths: Codable, Equatable, Sendable {
    private var values: [Tool: Double] = [:]

    public init() {}

    public subscript(tool: Tool) -> Double? {
        get { values[tool] }
        set { values[tool] = newValue }
    }

    public var isEmpty: Bool { values.isEmpty }

    func validated() -> StrokeWidths {
        var v = StrokeWidths()
        for (t, w) in values { v[t] = clampWidth(w, for: t) }
        return v
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: Double].self)
        for t in Tool.allCases { values[t] = raw[t.key] }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(Dictionary(uniqueKeysWithValues: values.map { ($0.key.key, $0.value) }))
    }
}

extension Tool {
    var key: String { "\(self)" }
}

public final class SettingsStore {
    public static let key = "settings.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> TracerSettings {
        guard let data = defaults.data(forKey: Self.key),
              let s = try? JSONDecoder().decode(TracerSettings.self, from: data) else { return .defaults }
        return s.validated()
    }

    public func save(_ s: TracerSettings) {
        if let data = try? JSONEncoder().encode(s.validated()) { defaults.set(data, forKey: Self.key) }
    }
}
