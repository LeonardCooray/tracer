import Testing
@testable import TracerCore

@Test func digitsMapToTools() {
    #expect(Tool.forDigit(1, mode: .drawing) == .pen)
    #expect(Tool.forDigit(6, mode: .drawing) == .text)
}

@Test func digitFiveDependsOnMode() {
    #expect(Tool.forDigit(5, mode: .capturing) == .redact)
    #expect(Tool.forDigit(5, mode: .drawing) == .spotlight)
    #expect(Tool.forDigit(6, mode: .capturing) == .text)
    #expect(Tool.forDigit(7, mode: .capturing) == nil && Tool.forDigit(0, mode: .drawing) == nil)
}

@Test func availabilityByMode() {
    #expect(!Tool.redact.isAvailable(in: .drawing) && Tool.redact.isAvailable(in: .capturing))
    #expect(!Tool.spotlight.isAvailable(in: .capturing) && Tool.spotlight.isAvailable(in: .drawing))
}

@Test func displayNames() {
    #expect(Tool.allCases.map(\.displayName) == ["Pen", "Highlighter", "Arrow", "Rectangle", "Spotlight", "Text", "Redact"])
}

@Test func pointerLabelShowsToolAndFade() {
    #expect(pointerLabel(tool: .rectangle, fadeDelay: 3, shiftHeld: false) == "Rectangle · fades 3s")
    #expect(pointerLabel(tool: .pen, fadeDelay: 2.5, shiftHeld: false) == "Pen · fades 2.5s")
    #expect(pointerLabel(tool: .arrow, fadeDelay: 3, shiftHeld: true) == "Arrow · stays")
    #expect(pointerLabel(tool: .spotlight, fadeDelay: 3, shiftHeld: false) == "Spotlight")
}
