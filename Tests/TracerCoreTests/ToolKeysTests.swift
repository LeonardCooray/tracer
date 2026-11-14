import Foundation
import Testing
@testable import TracerCore

private func freshDefaults() -> UserDefaults {
    let name = "tracer.tests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

private func drawing() -> Session {
    var s = Session()
    _ = s.handle(.penHotkey)
    return s
}

@Test func newKeysMap() {
    #expect(command(for: .tab, mode: .drawing, isEditingText: false) == .toggleTool)
    #expect(command(for: .leftBracket, mode: .capturing, isEditingText: false) == .thinner)
    #expect(command(for: .rightBracket, mode: .drawing, isEditingText: false) == .thicker)
    for key in [SessionKey.tab, .leftBracket, .rightBracket] {
        #expect(command(for: key, mode: .drawing, isEditingText: true) == nil)
        #expect(command(for: key, mode: .idle, isEditingText: false) == nil)
    }
}

@Test func newKeyCodesAreANSI() {
    #expect(KeyCode.tab == 48 && KeyCode.leftBracket == 33 && KeyCode.rightBracket == 30)
    #expect(Hotkey(keyCode: KeyCode.leftBracket, modifiers: 0).displayString == "[")
}

@Test func tabDoesNothingWithoutAPreviousTool() {
    var s = drawing()
    #expect(s.handle(.command(.toggleTool)).isEmpty)
    _ = s.handle(.command(.selectTool(.pen)))
    #expect(s.handle(.command(.toggleTool)).isEmpty)
    #expect(s.tool == .pen)
}

@Test func tabTogglesLastTwoTools() {
    var s = drawing()
    _ = s.handle(.command(.selectTool(.arrow)))
    _ = s.handle(.command(.selectTool(.rectangle)))
    #expect(s.handle(.command(.toggleTool)) == [.selectTool(.arrow)])
    #expect(s.handle(.command(.toggleTool)) == [.selectTool(.rectangle)])
    #expect(s.handle(.command(.toggleTool)) == [.selectTool(.arrow)])
}

@Test func tabSkipsToolsTheModeLacks() {
    var s = drawing()
    _ = s.handle(.command(.selectTool(.arrow)))
    _ = s.handle(.command(.selectTool(.spotlight)))
    _ = s.handle(.captureHotkey)
    #expect(s.tool == .pen)
    // Spotlight was used last but capture has none, so Tab goes to the arrow.
    #expect(s.handle(.command(.toggleTool)) == [.selectTool(.arrow)])
    #expect(s.handle(.command(.toggleTool)) == [.selectTool(.pen)])
}

@Test func tabSuppressedWhileTyping() {
    var s = drawing()
    _ = s.handle(.command(.selectTool(.text)))
    _ = s.handle(.textEditingBegan)
    #expect(command(for: .tab, mode: s.mode, isEditingText: s.isEditingText) == nil)
}

@Test func bracketsOnlyForToolsWithWidth() {
    var s = drawing()
    #expect(s.handle(.command(.thicker)) == [.stepWidth(thicker: true)])
    #expect(s.handle(.command(.thinner)) == [.stepWidth(thicker: false)])
    _ = s.handle(.command(.selectTool(.text)))
    #expect(s.handle(.command(.thicker)) == [.stepWidth(thicker: true)])
    _ = s.handle(.command(.selectTool(.spotlight)))
    #expect(s.handle(.command(.thicker)).isEmpty && s.handle(.command(.thinner)).isEmpty)
    _ = s.handle(.captureHotkey)
    _ = s.handle(.command(.selectTool(.redact)))
    #expect(s.handle(.command(.thicker)).isEmpty && s.handle(.command(.thinner)).isEmpty)
}

@Test func widthStepsAndClamps() {
    #expect(steppedWidth(4, for: .pen, thicker: true) == 6)
    #expect(steppedWidth(4, for: .pen, thicker: false) == 3)
    #expect(steppedWidth(24, for: .pen, thicker: true) == 24)
    #expect(steppedWidth(1, for: .pen, thicker: false) == 1)
    #expect(steppedWidth(3.5, for: .rectangle, thicker: true) == 4)
    #expect(steppedWidth(3.5, for: .rectangle, thicker: false) == 3)
    #expect(steppedWidth(18, for: .text, thicker: true) == 24)
    #expect(steppedWidth(72, for: .text, thicker: true) == 72)
    #expect(steppedWidth(18, for: .highlighter, thicker: false) == 12)
    #expect(steppedWidth(2, for: .highlighter, thicker: false) == 8)
    #expect(steppedWidth(4, for: .spotlight, thicker: true) == nil)
    #expect(steppedWidth(4, for: .redact, thicker: false) == nil)
}

@Test func defaultWidthsSitInsideTheirRange() {
    for t in Tool.allCases {
        guard let steps = widthSteps(for: t) else { continue }
        #expect(steps == steps.sorted() && steps.first! <= defaultWidth(for: t) && defaultWidth(for: t) <= steps.last!)
    }
}

@Test func sizeLabelReadsNaturally() {
    #expect(sizeLabel(tool: .pen, width: 6) == "Pen · 6 pt")
    #expect(sizeLabel(tool: .rectangle, width: 3.5) == "Rectangle · 3.5 pt")
    #expect(sizeLabel(tool: .text, width: 24) == "Text · 24 pt")
}

@Test func strokeWidthsDefaultToPerToolDefaults() {
    let s = TracerSettings.defaults
    #expect(s.strokeWidths.isEmpty)
    for t in Tool.allCases { #expect(s.strokeWidth(for: t) == defaultWidth(for: t)) }
}

@Test func strokeWidthsRoundTripByName() throws {
    let store = SettingsStore(defaults: freshDefaults())
    var s = TracerSettings.defaults
    s.strokeWidths[.pen] = 6
    s.strokeWidths[.text] = 32
    store.save(s)
    #expect(store.load() == s)
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]
    #expect((json?["strokeWidths"] as? [String: Double]) == ["pen": 6, "text": 32])
}

@Test func prefsWithoutStrokeWidthsLoadUnchanged() throws {
    let d = freshDefaults()
    var s = TracerSettings.defaults
    s.fadeDelay = 6
    s.format = .jpeg
    s.cursorRingAlwaysOn = true
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
    json["strokeWidths"] = nil
    d.set(try JSONSerialization.data(withJSONObject: json), forKey: SettingsStore.key)
    #expect(SettingsStore(defaults: d).load() == s)
}

@Test func badStrokeWidthsDontLosePrefs() throws {
    let d = freshDefaults()
    var s = TracerSettings.defaults
    s.fadeDelay = 7
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
    json["strokeWidths"] = "nonsense"
    d.set(try JSONSerialization.data(withJSONObject: json), forKey: SettingsStore.key)
    #expect(SettingsStore(defaults: d).load() == s)
}

@Test func strokeWidthsValidated() {
    var s = TracerSettings.defaults
    s.strokeWidths[.pen] = 500
    s.strokeWidths[.highlighter] = 1
    s.strokeWidths[.text] = .nan
    s.strokeWidths[.spotlight] = 9
    let v = s.validated()
    #expect(v.strokeWidths[.pen] == 24 && v.strokeWidths[.highlighter] == 8)
    #expect(v.strokeWidths[.text] == nil && v.strokeWidths[.spotlight] == nil)
}
