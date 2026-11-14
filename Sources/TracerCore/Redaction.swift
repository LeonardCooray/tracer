import Accelerate
import CoreGraphics
import Foundation

// `rect` is in the image's point space, origin bottom-left; returns whole pixels, origin top-left.
func pixelCrop(_ rect: CGRect, scale: Double, width: Int, height: Int) -> CGRect? {
    let px = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
    let clipped = px.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
    return CGRect(x: clipped.minX, y: Double(height) - clipped.maxY, width: clipped.width, height: clipped.height)
}

func pixelCrop(_ rect: CGRect, scale: Double, image: CGImage) -> CGRect? {
    pixelCrop(rect, scale: scale, width: image.width, height: image.height)
}

// A frozen frame's 8-bit pixels in its own colour space, read once so each box's mean is one vImage pass.
public struct FramePixels: Sendable {
    public let width: Int, height: Int
    public let space: CGColorSpace
    private let bytes: Data
    private let bytesPerRow: Int
    private let offsets: (r: Int, g: Int, b: Int)

    public init?(_ image: CGImage) {
        width = image.width
        height = image.height
        if let s = image.colorSpace, s.model == .rgb, image.bitsPerComponent == 8, image.bitsPerPixel == 32,
           image.pixelFormatInfo == .packed, !image.bitmapInfo.contains(.floatComponents),
           let o = Self.offsets(alpha: image.alphaInfo, order: image.byteOrderInfo),
           let d = image.dataProvider?.data as Data?, d.count >= image.bytesPerRow * (height - 1) + width * 4 {
            space = s; bytes = d; bytesPerRow = image.bytesPerRow; offsets = o
            return
        }
        // Other formats are drawn once into 8-bit RGBA, in the frame's own space when a bitmap can use it.
        let own = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
        for s in [own, CGColorSpace(name: CGColorSpace.sRGB)].compactMap({ $0 }) {
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: s,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let p = ctx.data else { continue }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            space = s; bytes = Data(bytes: p, count: width * 4 * height); bytesPerRow = width * 4; offsets = (0, 1, 2)
            return
        }
        return nil
    }

    private static func offsets(alpha: CGImageAlphaInfo, order: CGImageByteOrderInfo) -> (r: Int, g: Int, b: Int)? {
        let first: Bool
        switch alpha {
        case .first, .premultipliedFirst, .noneSkipFirst: first = true
        case .last, .premultipliedLast, .noneSkipLast: first = false
        default: return nil
        }
        switch order {
        case .orderDefault, .order32Big: return first ? (1, 2, 3) : (0, 1, 2)
        case .order32Little: return first ? (2, 1, 0) : (3, 2, 1)
        default: return nil
        }
    }

    // The mean of the pixels under `rect` (point space, origin bottom-left) in `space`; `maxSamples` reads every nth row instead.
    public func mean(in rect: CGRect, scale: Double, maxSamples: Int? = nil) -> RGBA? {
        guard let tl = pixelCrop(rect, scale: scale, width: width, height: height) else { return nil }
        let x = Int(tl.minX), y = Int(tl.minY), w = Int(tl.width), h = Int(tl.height)
        let step = maxSamples.map { min(h, max(1, (w * h + $0 - 1) / $0)) } ?? 1
        let rows = (h + step - 1) / step
        var bins = [vImagePixelCount](repeating: 0, count: 1024)
        let err = bytes.withUnsafeBytes { raw in
            bins.withUnsafeMutableBufferPointer { b in
                var buf = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: raw.baseAddress! + y * bytesPerRow + x * 4),
                                        height: vImagePixelCount(rows), width: vImagePixelCount(w), rowBytes: bytesPerRow * step)
                var hist: [UnsafeMutablePointer<vImagePixelCount>?] = (0..<4).map { b.baseAddress! + $0 * 256 }
                return vImageHistogramCalculation_ARGB8888(&buf, &hist, vImage_Flags(kvImageNoFlags))
            }
        }
        guard err == kvImageNoError else { return nil }
        let n = Double(rows * w) * 255
        func channel(_ c: Int) -> Double { (0..<256).reduce(0.0) { $0 + Double($1) * Double(bins[c * 256 + $1]) } / n }
        return RGBA(r: channel(offsets.r), g: channel(offsets.g), b: channel(offsets.b))
    }
}
