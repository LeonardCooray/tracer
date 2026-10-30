import CoreGraphics

public enum Compositor {
    // `selection` is in the base image's point space, origin bottom-left.
    public static func image(base: CGImage, baseScale: Double, strokes: [Stroke], selection: CGRect) -> CGImage? {
        let px = CGRect(x: selection.minX * baseScale, y: selection.minY * baseScale,
                        width: selection.width * baseScale, height: selection.height * baseScale).integral
        let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let clipped = px.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        let topLeft = CGRect(x: clipped.minX, y: Double(base.height) - clipped.maxY, width: clipped.width, height: clipped.height)
        guard let crop = base.cropping(to: topLeft),
              let ctx = CGContext(data: nil, width: Int(clipped.width), height: Int(clipped.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: clipped.width, height: clipped.height))
        ctx.translateBy(x: -clipped.minX, y: -clipped.minY)
        ctx.scaleBy(x: baseScale, y: baseScale)
        InkRenderer.draw(strokes.filter { $0.tool != .spotlight }, in: ctx) { _ in 1 }
        return ctx.makeImage()
    }
}
