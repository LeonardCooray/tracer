// Draws the app icon and writes Resources/AppIcon.icns. Usage: swift scripts/icon.swift [preview.png]
import AppKit

let size = 1024.0
let ink = CGColor(srgbRed: 1, green: 0.271, blue: 0.227, alpha: 1)

func squircle(_ r: CGRect, n: Double = 5) -> CGPath {
    let p = CGMutablePath()
    for i in 0...720 {
        let t = Double(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * copysign(pow(abs(c), 2 / n), c)
        let y = r.midY + r.height / 2 * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func render() -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(tile)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.09, blue: 0.23, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: rgb, colors: [CGColor(srgbRed: 0.20, green: 0.22, blue: 0.52, alpha: 1),
                                                   CGColor(srgbRed: 0.07, green: 0.08, blue: 0.22, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: tile.maxY), end: CGPoint(x: 700, y: tile.minY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let sheen = CGGradient(colorsSpace: rgb, colors: [CGColor(gray: 1, alpha: 0.14), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 360, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 360, y: 860), endRadius: 520, options: [])

    // Capture corners
    let frame = CGRect(x: 238, y: 238, width: 548, height: 548), arm = 118.0
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.88))
    ctx.setLineWidth(28)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (x, y, dx, dy) in [(frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
                           (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0)] {
        ctx.move(to: CGPoint(x: x, y: y + dy * arm))
        ctx.addLine(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x + dx * arm, y: y))
        ctx.strokePath()
    }

    // Ink loop that fades from its oldest end, like Tracer's ink
    let center = CGPoint(x: 512, y: 506), rx = 196.0, ry = 132.0, tilt = -0.28
    let steps = 260
    var pts: [CGPoint] = []
    for i in 0...steps {
        let u = Double(i) / Double(steps)
        let t = 3.55 + u * 2 * .pi * 1.12
        let wob = 1 + 0.05 * sin(2.3 * t + 0.6) + 0.07 * u
        let x = rx * wob * cos(t), y = ry * wob * sin(t)
        pts.append(CGPoint(x: center.x + x * cos(tilt) - y * sin(tilt), y: center.y + x * sin(tilt) + y * cos(tilt)))
    }
    ctx.setLineCap(.round)
    ctx.setShadow(offset: .zero, blur: 26, color: CGColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 0.45))
    for i in 1..<pts.count {
        let u = Double(i) / Double(steps)
        ctx.setStrokeColor(ink.copy(alpha: min(1, 0.04 + 1.1 * pow(u, 1.3)))!)
        ctx.setLineWidth(26 + 20 * u)
        ctx.move(to: pts[i - 1])
        ctx.addLine(to: pts[i])
        ctx.strokePath()
    }
    ctx.restoreGState()
    return ctx.makeImage()!
}

func png(_ image: CGImage, _ px: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    g.imageInterpolation = .high
    NSGraphicsContext.current = g
    NSImage(cgImage: image, size: NSSize(width: size, height: size)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let image = render()
let args = CommandLine.arguments
if args.count > 1 {
    png(image, 1024, to: URL(fileURLWithPath: args[1]))
    exit(0)
}
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    png(image, pt, to: set.appendingPathComponent("icon_\(pt)x\(pt).png"))
    png(image, pt * 2, to: set.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
