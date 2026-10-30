import CoreGraphics
import Testing
@testable import TracerCore

@Test func tinySelectionIsNil() {
    #expect(selectionRect(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 7, y: 8)) == nil)
    #expect(selectionRect(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5)) == nil)
    #expect(selectionRect(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 10, y: 20)) == CGRect(x: 10, y: 20, width: 40, height: 30))
}

private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let dock = CGSize(width: 38, height: 300)

@Test func dockSitsRightOfSelection() {
    let sel = CGRect(x: 300, y: 300, width: 400, height: 200)
    let o = dockOrigin(selection: sel, dockSize: dock, screen: screen)
    #expect(o.x == sel.maxX + 8)
    #expect(o.y + dock.height <= screen.maxY && o.y >= screen.minY)
}

@Test func dockFlipsNearRightEdge() {
    let sel = CGRect(x: 1100, y: 300, width: 400, height: 200)
    let o = dockOrigin(selection: sel, dockSize: dock, screen: screen)
    #expect(o.x == sel.minX - 8 - dock.width)
}

@Test func dockGoesInsideWhenNoRoomEitherSide() {
    let sel = CGRect(x: 5, y: 100, width: 1500, height: 600)
    let o = dockOrigin(selection: sel, dockSize: dock, screen: screen)
    #expect(o.x >= screen.minX && o.x + dock.width <= screen.maxX)
}

@Test func dockClampsVertically() {
    let top = dockOrigin(selection: CGRect(x: 300, y: 900, width: 200, height: 82), dockSize: dock, screen: screen)
    #expect(top.y + dock.height <= screen.maxY)
    let bottom = dockOrigin(selection: CGRect(x: 300, y: 0, width: 200, height: 40), dockSize: dock, screen: screen)
    #expect(bottom.y >= screen.minY)
}

@Test func dockAlignsWithSelectionTop() {
    let sel = CGRect(x: 300, y: 300, width: 400, height: 400)
    let o = dockOrigin(selection: sel, dockSize: dock, screen: screen)
    #expect(o.y + dock.height == sel.maxY)
}

@Test func sizeLabelUsesPixels() {
    #expect(sizeLabel(selection: CGRect(x: 0, y: 0, width: 620, height: 340), scale: 2, format: .png) == "1240 × 680 · PNG")
    #expect(sizeLabel(selection: CGRect(x: 0, y: 0, width: 100.4, height: 50), scale: 1, format: .jpeg) == "100 × 50 · JPEG")
}
