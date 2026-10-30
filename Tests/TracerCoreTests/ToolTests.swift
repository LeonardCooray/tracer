import Testing
@testable import TracerCore

@Test func digitsMapToTools() {
    #expect(Tool.forDigit(1) == .pen)
    #expect(Tool.forDigit(6) == .text)
    #expect(Tool.forDigit(0) == nil)
    #expect(Tool.forDigit(7) == nil)
}

@Test func spotlightIsLiveOnly() {
    #expect(!Tool.spotlight.availableInCapture)
    #expect(Tool.allCases.filter { !$0.availableInCapture } == [.spotlight])
}

@Test func displayNames() {
    #expect(Tool.allCases.map(\.displayName) == ["Pen", "Highlighter", "Arrow", "Rectangle", "Spotlight", "Text"])
}

@Test func pointerLabelShowsToolAndFade() {
    #expect(pointerLabel(tool: .rectangle, fadeDelay: 3, shiftHeld: false) == "Rectangle · fades 3s")
    #expect(pointerLabel(tool: .pen, fadeDelay: 2.5, shiftHeld: false) == "Pen · fades 2.5s")
    #expect(pointerLabel(tool: .arrow, fadeDelay: 3, shiftHeld: true) == "Arrow · stays")
    #expect(pointerLabel(tool: .spotlight, fadeDelay: 3, shiftHeld: false) == "Spotlight")
}
