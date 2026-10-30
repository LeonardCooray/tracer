import CoreGraphics
import Testing
@testable import TracerCore

private let red = StrokeStyle(color: InkPalette.presets[0], width: 4)

private func finishedStroke(_ m: InkModel, at time: Double, pinned: Bool = false) {
    m.begin(tool: .pen, style: red, at: .zero, pinned: pinned)
    m.extend(to: CGPoint(x: 10, y: 0))
    m.end(at: time)
}

@Test func liveStrokeHoldsThenFades() {
    let m = InkModel(mode: .live(delay: 3))
    finishedStroke(m, at: 100)
    let k = m.strokes[0]
    #expect(m.opacity(of: k, at: 102.9) == 1)
    let mid = m.opacity(of: k, at: 103.2)
    #expect(mid > 0 && mid < 1)
    #expect(m.opacity(of: k, at: 103.4) == 0)
}

@Test func strokeInProgressIsOpaque() {
    let m = InkModel(mode: .live(delay: 3))
    m.begin(tool: .pen, style: red, at: .zero, pinned: false)
    #expect(m.opacity(of: m.strokes[0], at: 10_000) == 1)
}

@Test func pinnedNeverFades() {
    let m = InkModel(mode: .live(delay: 3))
    finishedStroke(m, at: 100, pinned: true)
    #expect(m.opacity(of: m.strokes[0], at: 10_000) == 1)
}

@Test func frozenNeverFades() {
    let m = InkModel(mode: .frozen)
    finishedStroke(m, at: 100)
    #expect(m.opacity(of: m.strokes[0], at: 10_000) == 1)
}

@Test func pruneDropsOnlyFullyFaded() {
    let m = InkModel(mode: .live(delay: 3))
    finishedStroke(m, at: 100)
    finishedStroke(m, at: 105)
    m.prune(at: 103.5)
    #expect(m.strokes.count == 1)
    #expect(m.strokes[0].finishedAt == 105)
}

@Test func undoRemovesLastAndClearRemovesAll() {
    let m = InkModel(mode: .live(delay: 3))
    finishedStroke(m, at: 1)
    finishedStroke(m, at: 2)
    m.undo()
    #expect(m.strokes.count == 1)
    #expect(m.strokes[0].finishedAt == 1)
    finishedStroke(m, at: 3)
    m.clear()
    #expect(m.strokes.isEmpty)
}

@Test func extendSkipsNearDuplicatePoints() {
    let m = InkModel(mode: .live(delay: 3))
    m.begin(tool: .pen, style: red, at: .zero, pinned: false)
    m.extend(to: CGPoint(x: 0.2, y: 0.2))
    m.extend(to: CGPoint(x: 5, y: 0))
    #expect(m.strokes[0].points.count == 2)
}

@Test func addTextStoresFinishedStroke() {
    let m = InkModel(mode: .live(delay: 3))
    m.addText("Look here", at: CGPoint(x: 20, y: 30), style: red, time: 50)
    let s = m.strokes[0]
    #expect(s.tool == .text)
    #expect(s.text == "Look here")
    #expect(s.points == [CGPoint(x: 20, y: 30)])
    #expect(s.finishedAt == 50)
}

@Test func fadeSettingClamps() {
    #expect(FadeSetting.clamp(0.2) == 1)
    #expect(FadeSetting.clamp(30) == 10)
    #expect(FadeSetting.clamp(4) == 4)
    #expect(FadeSetting.defaultDelay == 3)
}

@Test func defaultWidths() {
    #expect(defaultWidth(for: .pen) == 4)
    #expect(defaultWidth(for: .highlighter) == 18)
    #expect(defaultWidth(for: .rectangle) == 3.5)
    #expect(defaultWidth(for: .text) == 18)
}

@Test func paletteHasFivePresets() {
    #expect(InkPalette.presets.count == 5)
    #expect(InkPalette.presets[0] == RGBA(hex: 0xFF453A))
}

@Test func removeStrokeByID() {
    let m = InkModel(mode: .live(delay: 3))
    finishedStroke(m, at: 1)
    finishedStroke(m, at: 2)
    let firstID = m.strokes[0].id
    #expect(m.remove(id: firstID))
    #expect(m.strokes.count == 1 && m.strokes[0].finishedAt == 2)
    #expect(!m.remove(id: firstID))
}

@Test func tracksStrokeInProgress() {
    let m = InkModel(mode: .live(delay: 3))
    #expect(!m.isDrawing)
    m.begin(tool: .pen, style: red, at: .zero, pinned: false)
    #expect(m.isDrawing)
    m.end(at: 1)
    #expect(!m.isDrawing)
}
