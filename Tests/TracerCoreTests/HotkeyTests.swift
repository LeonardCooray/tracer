import CoreGraphics
import Foundation
import Testing
@testable import TracerCore

@Test func defaultDisplayStrings() {
    #expect(Hotkey.defaultPen.displayString == "⌥⇧D")
    #expect(Hotkey.defaultCapture.displayString == "⌥⇧S")
}

@Test func modifierOrderIsControlOptionShiftCommand() {
    let all = Hotkey(keyCode: KeyCode.a, modifiers: Hotkey.control | Hotkey.option | Hotkey.shift | Hotkey.command)
    #expect(all.displayString == "⌃⌥⇧⌘A")
}

@Test func systemScreenshotKeysAreReserved() {
    for code in [KeyCode.three, KeyCode.four, KeyCode.five, KeyCode.six] {
        #expect(Hotkey(keyCode: code, modifiers: Hotkey.shift | Hotkey.command).isReservedBySystem)
    }
    #expect(!Hotkey.defaultPen.isReservedBySystem)
    #expect(!Hotkey.defaultCapture.isReservedBySystem)
    #expect(!Hotkey(keyCode: KeyCode.four, modifiers: Hotkey.shift).isReservedBySystem)
}

@Test func hotkeyRoundTripsThroughJSON() throws {
    let data = try JSONEncoder().encode(Hotkey.defaultPen)
    #expect(try JSONDecoder().decode(Hotkey.self, from: data) == .defaultPen)
}

@Test func unknownKeyCodeStillDisplays() {
    #expect(Hotkey(keyCode: 200, modifiers: Hotkey.option).displayString == "⌥Key 200")
}

@Test func fadingTrackedOnlyForUnpinnedFinishedLiveInk() {
    let style = StrokeStyle(color: InkPalette.presets[0], width: 4)
    let m = InkModel(mode: .live(delay: 3))
    m.begin(tool: .pen, style: style, at: .zero, pinned: true)
    m.end(at: 1)
    #expect(!m.hasFadingStrokes)
    m.begin(tool: .pen, style: style, at: .zero, pinned: false)
    #expect(!m.hasFadingStrokes)
    m.end(at: 2)
    #expect(m.hasFadingStrokes)
    m.mode = .frozen
    #expect(!m.hasFadingStrokes)
}

@Test func recorderProblems() {
    let cap = Hotkey.defaultCapture
    #expect(hotkeyProblem(cap, other: cap, otherName: "Capture") == "Already used for Capture")
    #expect(hotkeyProblem(Hotkey(keyCode: KeyCode.four, modifiers: Hotkey.shift | Hotkey.command), other: cap, otherName: "Capture") == "⇧⌘4 is used by macOS")
    #expect(hotkeyProblem(Hotkey(keyCode: KeyCode.a, modifiers: Hotkey.shift), other: cap, otherName: "Capture") == "Add ⌃, ⌥ or ⌘")
    #expect(hotkeyProblem(Hotkey(keyCode: KeyCode.a, modifiers: Hotkey.control), other: cap, otherName: "Capture") == nil)
}
