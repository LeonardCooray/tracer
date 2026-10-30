import CoreGraphics
import Foundation

public enum FadeMode: Equatable, Sendable {
    case live(delay: Double)
    case frozen
}

public enum FadeSetting {
    public static let range = 1.0...10.0
    public static let defaultDelay = 3.0
    public static func clamp(_ v: Double) -> Double { min(max(v, range.lowerBound), range.upperBound) }
}

public final class InkModel {
    public static let fadeOutDuration = 0.4
    public var mode: FadeMode
    public private(set) var strokes: [Stroke] = []
    private var activeIndex: Int?

    public init(mode: FadeMode) { self.mode = mode }

    public func begin(tool: Tool, style: StrokeStyle, at point: CGPoint, pinned: Bool) {
        strokes.append(Stroke(tool: tool, points: [point], style: style, pinned: pinned))
        activeIndex = strokes.count - 1
    }

    public func extend(to point: CGPoint) {
        guard let i = activeIndex, let last = strokes[i].points.last else { return }
        if hypot(point.x - last.x, point.y - last.y) < 0.5 { return }
        strokes[i].points.append(point)
    }

    public func end(at time: TimeInterval) {
        guard let i = activeIndex else { return }
        strokes[i].finishedAt = time
        activeIndex = nil
    }

    public func addText(_ text: String, at point: CGPoint, style: StrokeStyle, time: TimeInterval) {
        strokes.append(Stroke(tool: .text, points: [point], style: style, text: text, finishedAt: time))
    }

    public func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        activeIndex = nil
    }

    public func clear() {
        strokes.removeAll()
        activeIndex = nil
    }

    public func opacity(of stroke: Stroke, at time: TimeInterval) -> Double {
        guard case .live(let delay) = mode, !stroke.pinned, let done = stroke.finishedAt else { return 1 }
        let elapsed = time - done - delay
        if elapsed <= 0 { return 1 }
        return max(0, 1 - elapsed / Self.fadeOutDuration)
    }

    public var hasFadingStrokes: Bool {
        guard case .live = mode else { return false }
        return strokes.contains { !$0.pinned && $0.finishedAt != nil }
    }

    public func prune(at time: TimeInterval) {
        let active = activeIndex.map { strokes[$0].id }
        strokes.removeAll { $0.id != active && opacity(of: $0, at: time) == 0 }
        activeIndex = active.flatMap { id in strokes.firstIndex { $0.id == id } }
    }
}
