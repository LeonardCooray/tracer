import CoreGraphics

// `rect` is in the image's point space, origin bottom-left; returns whole pixels, origin top-left.
func pixelCrop(_ rect: CGRect, scale: Double, image: CGImage) -> CGRect? {
    let px = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
    let clipped = px.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
    return CGRect(x: clipped.minX, y: Double(image.height) - clipped.maxY, width: clipped.width, height: clipped.height)
}

// The sRGB mean of the pixels under `rect`; `maxSide` downsamples first, for cheap previews.
public func meanColor(of image: CGImage, scale: Double, in rect: CGRect, maxSide: Int? = nil) -> RGBA? {
    guard let tl = pixelCrop(rect, scale: scale, image: image), let crop = image.cropping(to: tl) else { return nil }
    let f = maxSide.map { min(1, Double($0) / max(tl.width, tl.height)) } ?? 1
    let w = max(1, Int((tl.width * f).rounded())), h = max(1, Int((tl.height * f).rounded()))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let data = ctx.data
    else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = data.assumingMemoryBound(to: UInt8.self)
    var r = 0, g = 0, b = 0
    for i in stride(from: 0, to: w * h * 4, by: 4) { r += Int(p[i]); g += Int(p[i + 1]); b += Int(p[i + 2]) }
    let n = Double(w * h) * 255
    return RGBA(r: Double(r) / n, g: Double(g) / n, b: Double(b) / n)
}
