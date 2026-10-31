import Testing
@testable import TracerCore

@Test func keysMap() {
    #expect(command(for: .digit(3), mode: .drawing, isEditingText: false) == .selectTool(.arrow))
    #expect(command(for: .delete, mode: .drawing, isEditingText: false) == .clearAll)
    #expect(command(for: .undo, mode: .drawing, isEditingText: false) == .undo)
    #expect(command(for: .redo, mode: .drawing, isEditingText: false) == .redo)
    #expect(command(for: .redo, mode: .capturing, isEditingText: false) == .redo)
    #expect(command(for: .returnKey, mode: .capturing, isEditingText: false) == .copy)
    #expect(command(for: .copy, mode: .capturing, isEditingText: false) == .copy)
    #expect(command(for: .save, mode: .capturing, isEditingText: false) == .save)
}

@Test func unknownDigitIsNil() {
    #expect(command(for: .digit(9), mode: .drawing, isEditingText: false) == nil)
}

@Test func keysSuppressedWhileTyping() {
    for key in [SessionKey.digit(1), .delete, .undo, .redo, .returnKey, .copy, .save] {
        #expect(command(for: key, mode: .drawing, isEditingText: true) == nil)
        #expect(command(for: key, mode: .capturing, isEditingText: true) == nil)
    }
}

@Test func copySaveOnlyInCapture() {
    #expect(command(for: .returnKey, mode: .drawing, isEditingText: false) == nil)
    #expect(command(for: .copy, mode: .drawing, isEditingText: false) == nil)
    #expect(command(for: .save, mode: .drawing, isEditingText: false) == nil)
}

@Test func nothingWhenIdleOrEscape() {
    #expect(command(for: .digit(1), mode: .idle, isEditingText: false) == nil)
    #expect(command(for: .escape, mode: .drawing, isEditingText: false) == nil)
}

@Test func digitFiveIsRedactWhileCapturing() {
    #expect(command(for: .digit(5), mode: .capturing, isEditingText: false) == .selectTool(.redact))
    #expect(command(for: .digit(5), mode: .drawing, isEditingText: false) == .selectTool(.spotlight))
}
