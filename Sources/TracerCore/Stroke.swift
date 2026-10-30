import CoreGraphics
import Foundation

public struct Stroke: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var tool: Tool
    public var points: [CGPoint]
    public var style: StrokeStyle
    public var pinned: Bool
    public var text: String?
    public var finishedAt: TimeInterval?

    public init(id: UUID = UUID(), tool: Tool, points: [CGPoint], style: StrokeStyle,
                pinned: Bool = false, text: String? = nil, finishedAt: TimeInterval? = nil) {
        self.id = id; self.tool = tool; self.points = points; self.style = style
        self.pinned = pinned; self.text = text; self.finishedAt = finishedAt
    }
}
