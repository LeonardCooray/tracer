import Testing
@testable import TracerCore

private let exitEffects: [SessionEffect] = [.hideOverlays, .clearInk, .unregisterSessionKeys, .restorePreviousApp]

@Test func penHotkeyTogglesDrawing() {
    var s = Session()
    #expect(s.handle(.penHotkey) == [.showOverlays(interactive: true), .setFadeMode(.live(delay: 3)), .registerSessionKeys(capture: false)])
    #expect(s.mode == .drawing)
    #expect(s.handle(.penHotkey) == exitEffects)
    #expect(s.mode == .idle)
}

@Test func escapeLeavesDrawingAndClears() {
    var s = Session()
    _ = s.handle(.penHotkey)
    #expect(s.handle(.escape) == exitEffects)
    #expect(s.mode == .idle)
}

@Test func escapeWhenIdleDoesNothing() {
    var s = Session()
    #expect(s.handle(.escape).isEmpty)
}

@Test func fadeDelayFollowsSetting() {
    var s = Session(fadeDelay: 5)
    #expect(s.handle(.penHotkey).contains(.setFadeMode(.live(delay: 5))))
    _ = s.handle(.penHotkey)
    s.setFadeDelay(7)
    #expect(s.handle(.penHotkey).contains(.setFadeMode(.live(delay: 7))))
}

@Test func captureFromIdleFreezes() {
    var s = Session()
    #expect(s.handle(.captureHotkey) == [.freezeScreens, .showOverlays(interactive: true), .setFadeMode(.frozen), .registerSessionKeys(capture: true)])
    #expect(s.mode == .capturing)
}

@Test func captureFromDrawingKeepsInk() {
    var s = Session()
    _ = s.handle(.penHotkey)
    let fx = s.handle(.captureHotkey)
    #expect(fx == [.freezeScreens, .setFadeMode(.frozen), .registerSessionKeys(capture: true)])
    #expect(!fx.contains(.clearInk))
    #expect(s.mode == .capturing)
}

@Test func hotkeysIgnoredWhileCapturing() {
    var s = Session()
    _ = s.handle(.captureHotkey)
    #expect(s.handle(.captureHotkey).isEmpty)
    #expect(s.handle(.penHotkey).isEmpty)
    #expect(s.mode == .capturing)
}

@Test func copyAndSaveEndCapture() {
    var s = Session()
    _ = s.handle(.captureHotkey)
    #expect(s.handle(.command(.copy)) == [.copySelection])
    #expect(s.handle(.captureFinished) == exitEffects)
    #expect(s.mode == .idle)
    _ = s.handle(.captureHotkey)
    #expect(s.handle(.command(.save)) == [.saveSelection])
}

@Test func escapeCancelsCapture() {
    var s = Session()
    _ = s.handle(.captureHotkey)
    #expect(s.handle(.escape) == exitEffects)
    #expect(s.mode == .idle)
}

@Test func copySaveIgnoredWhileDrawing() {
    var s = Session()
    _ = s.handle(.penHotkey)
    #expect(s.handle(.command(.copy)).isEmpty)
    #expect(s.handle(.command(.save)).isEmpty)
}

@Test func toolSelectionAndEditing() {
    var s = Session()
    _ = s.handle(.penHotkey)
    #expect(s.handle(.command(.selectTool(.arrow))) == [.selectTool(.arrow)])
    #expect(s.tool == .arrow)
    #expect(s.handle(.command(.undo)) == [.undo])
    #expect(s.handle(.command(.clearAll)) == [.clearAll])
}

@Test func spotlightNotSelectableInCapture() {
    var s = Session()
    _ = s.handle(.captureHotkey)
    #expect(s.handle(.command(.selectTool(.spotlight))).isEmpty)
    #expect(s.tool == .pen)
}

@Test func enteringCaptureWithSpotlightFallsBackToPen() {
    var s = Session()
    _ = s.handle(.penHotkey)
    _ = s.handle(.command(.selectTool(.spotlight)))
    let fx = s.handle(.captureHotkey)
    #expect(s.tool == .pen)
    #expect(fx.contains(.selectTool(.pen)))
}

@Test func commandsIgnoredWhenIdle() {
    var s = Session()
    #expect(s.handle(.command(.selectTool(.arrow))).isEmpty)
    #expect(s.handle(.command(.clearAll)).isEmpty)
}

@Test func textEditingReleasesSessionKeys() {
    var s = Session()
    _ = s.handle(.penHotkey)
    #expect(s.handle(.textEditingBegan) == [.unregisterSessionKeys])
    #expect(s.isEditingText)
    #expect(s.handle(.textEditingEnded) == [.registerSessionKeys(capture: false)])
    #expect(!s.isEditingText)
}

@Test func escapeWhileEditingTextOnlyEndsText() {
    var s = Session()
    _ = s.handle(.penHotkey)
    _ = s.handle(.textEditingBegan)
    let fx = s.handle(.escape)
    #expect(s.mode == .drawing)
    #expect(!s.isEditingText)
    #expect(!fx.contains(.hideOverlays))
}

@Test func leavingDrawingResetsTextEditing() {
    var s = Session()
    _ = s.handle(.penHotkey)
    _ = s.handle(.textEditingBegan)
    _ = s.handle(.penHotkey)
    #expect(!s.isEditingText)
    #expect(s.mode == .idle)
}
