import CoreGraphics

public enum Compositor {
    // `selection` is in the base image's point space, origin bottom-left.
    public static func image(base: CGImage, baseScale: Double, strokes: [Stroke], selection: CGRect) -> CGImage? {
        guard let topLeft = pixelCrop(selection, scale: baseScale, image: base), let crop = base.cropping(to: topLeft),
              let ctx = CGContext(data: nil, width: Int(topLeft.width), height: Int(topLeft.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: topLeft.width, height: topLeft.height))
        ctx.translateBy(x: -topLeft.minX, y: -(Double(base.height) - topLeft.maxY))
        ctx.scaleBy(x: baseScale, y: baseScale)
        InkRenderer.draw(strokes.filter { $0.tool != .spotlight }, in: ctx, highlighterBlend: .multiply) { _ in 1 }
        return ctx.makeImage()
    }
}
