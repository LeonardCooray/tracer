import Foundation

public struct TracerSettings: Codable, Equatable, Sendable {
    public var penHotkey: Hotkey
    public var captureHotkey: Hotkey
    public var fadeDelay: Double
    public var saveFolder: URL
    public var format: ImageFormat
    public var launchAtLogin: Bool
    public var cursorRingAlwaysOn: Bool

    public static let defaults = TracerSettings(
        penHotkey: .defaultPen, captureHotkey: .defaultCapture, fadeDelay: FadeSetting.defaultDelay,
        saveFolder: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Tracer"),
        format: .png, launchAtLogin: false, cursorRingAlwaysOn: false)

    public func validated() -> TracerSettings {
        var s = self
        s.fadeDelay = FadeSetting.clamp(fadeDelay)
        if !s.penHotkey.isUsableGlobally { s.penHotkey = .defaultPen }
        if !s.captureHotkey.isUsableGlobally { s.captureHotkey = .defaultCapture }
        if s.penHotkey == s.captureHotkey {
            s.penHotkey = .defaultPen
            s.captureHotkey = .defaultCapture
        }
        return s
    }
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
