import Foundation
import Testing
@testable import TracerCore

private func freshDefaults() -> UserDefaults {
    let name = "tracer.tests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Test func defaultsAreAsSpecified() {
    let d = TracerSettings.defaults
    #expect(d.penHotkey == .defaultPen)
    #expect(d.captureHotkey == .defaultCapture)
    #expect(d.fadeDelay == 3)
    #expect(d.saveFolder.path.hasSuffix("/Pictures/Tracer"))
    #expect(d.format == .png)
    #expect(!d.launchAtLogin)
    #expect(!d.cursorRingAlwaysOn)
}

@Test func emptyStoreLoadsDefaults() {
    #expect(SettingsStore(defaults: freshDefaults()).load() == .defaults)
}

@Test func settingsRoundTrip() {
    let store = SettingsStore(defaults: freshDefaults())
    var s = TracerSettings.defaults
    s.fadeDelay = 6
    s.format = .jpeg
    s.cursorRingAlwaysOn = true
    s.saveFolder = URL(fileURLWithPath: "/tmp/shots")
    store.save(s)
    #expect(store.load() == s)
}

@Test func corruptBlobLoadsDefaults() {
    let d = freshDefaults()
    d.set(Data("not json".utf8), forKey: SettingsStore.key)
    #expect(SettingsStore(defaults: d).load() == .defaults)
}

@Test func validatedClampsFade() {
    var s = TracerSettings.defaults
    s.fadeDelay = 0
    #expect(s.validated().fadeDelay == 1)
    s.fadeDelay = 40
    #expect(s.validated().fadeDelay == 10)
}

@Test func duplicateHotkeysResetToDefaults() {
    var s = TracerSettings.defaults
    let k = Hotkey(keyCode: KeyCode.a, modifiers: Hotkey.control)
    s.penHotkey = k
    s.captureHotkey = k
    let v = s.validated()
    #expect(v.penHotkey == .defaultPen && v.captureHotkey == .defaultCapture)
}

@Test func reservedHotkeyResets() {
    var s = TracerSettings.defaults
    s.captureHotkey = Hotkey(keyCode: KeyCode.four, modifiers: Hotkey.shift | Hotkey.command)
    s.penHotkey = Hotkey(keyCode: KeyCode.a, modifiers: Hotkey.control)
    let v = s.validated()
    #expect(v.captureHotkey == .defaultCapture)
    #expect(v.penHotkey == Hotkey(keyCode: KeyCode.a, modifiers: Hotkey.control))
}

@Test func hotkeyWithoutModifiersResets() {
    var s = TracerSettings.defaults
    s.penHotkey = Hotkey(keyCode: KeyCode.d, modifiers: 0)
    #expect(s.validated().penHotkey == .defaultPen)
}

@Test func loadValidates() {
    let d = freshDefaults()
    var s = TracerSettings.defaults
    s.fadeDelay = 99
    d.set(try! JSONEncoder().encode(s), forKey: SettingsStore.key)
    #expect(SettingsStore(defaults: d).load().fadeDelay == 10)
}

@Test func shiftOnlyHotkeyResets() {
    var s = TracerSettings.defaults
    s.penHotkey = Hotkey(keyCode: KeyCode.a, modifiers: Hotkey.shift)
    #expect(s.validated().penHotkey == .defaultPen)
    #expect(!Hotkey(keyCode: KeyCode.a, modifiers: Hotkey.shift).isUsableGlobally)
    #expect(Hotkey(keyCode: KeyCode.a, modifiers: Hotkey.shift | Hotkey.option).isUsableGlobally)
}
