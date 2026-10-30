import CoreGraphics
import Foundation

public func arrowHead(from: CGPoint, to: CGPoint, width: Double) -> (CGPoint, CGPoint) {
    let angle = atan2(to.y - from.y, to.x - from.x)
    let length = max(12, width * 3.5)
    let spread = 28 * Double.pi / 180
    func wing(_ a: Double) -> CGPoint {
        CGPoint(x: to.x - length * cos(a), y: to.y - length * sin(a))
    }
    return (wing(angle + spread), wing(angle - spread))
}

public let minimumSelectionSide = 4.0

public func selectionRect(from a: CGPoint, to b: CGPoint) -> CGRect? {
    let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    return r.width < minimumSelectionSide || r.height < minimumSelectionSide ? nil : r
}

// Right of the selection, else left of it, else just inside its right edge; top-aligned and kept on screen.
public func dockOrigin(selection: CGRect, dockSize: CGSize, screen: CGRect, gap: Double = 8) -> CGPoint {
    var x = selection.maxX + gap
    if x + dockSize.width > screen.maxX {
        x = selection.minX - gap - dockSize.width
        if x < screen.minX { x = min(selection.maxX, screen.maxX) - gap - dockSize.width }
    }
    x = min(max(x, screen.minX), screen.maxX - dockSize.width)
    let y = min(max(selection.maxY - dockSize.height, screen.minY), screen.maxY - dockSize.height)
    return CGPoint(x: x, y: y)
}

public func sizeLabel(selection: CGRect, scale: Double, format: ImageFormat) -> String {
    "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded())) · \(format.label)"
}
