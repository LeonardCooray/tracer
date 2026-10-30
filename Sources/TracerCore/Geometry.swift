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
