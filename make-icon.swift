// Renders AppIcon.png with CoreGraphics: a glass bottle two-thirds full on a
// deep-water squircle. Run via ./make-icon.sh, which scales it into an
// .iconset and packs it with iconutil.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("could not create bitmap context")
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

// macOS icons leave a margin around the rounded square.
let inset = size * 0.094
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = rect.width * 0.2237
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x1B5FD6), rgb(0x0E2D7A), rgb(0x081A4A)], [0, 0.55, 1]),
                       start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
// A soft glow behind the bottle.
ctx.drawRadialGradient(gradient([rgb(0x5FD3FF, 0.45), rgb(0x5FD3FF, 0)], [0, 1]),
                       startCenter: CGPoint(x: rect.midX, y: rect.midY - 40), startRadius: 0,
                       endCenter: CGPoint(x: rect.midX, y: rect.midY - 40), endRadius: rect.width * 0.48, options: [])
ctx.restoreGState()

// The classic bottle from the app, in its 100 × 220 design space (y down).
func bottle(_ w: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let nl = 36 + w, nr = 64 - w, bl = 8 + w, br = 92 - w
    let bottom = 218 - w, r = 22 - w * 0.5
    p.move(to: CGPoint(x: nl, y: 26))
    p.addLine(to: CGPoint(x: nl, y: 44))
    p.addCurve(to: CGPoint(x: bl, y: 84), control1: CGPoint(x: nl, y: 60), control2: CGPoint(x: bl, y: 58))
    p.addLine(to: CGPoint(x: bl, y: bottom - r))
    p.addQuadCurve(to: CGPoint(x: bl + r, y: bottom), control: CGPoint(x: bl, y: bottom))
    p.addLine(to: CGPoint(x: br - r, y: bottom))
    p.addQuadCurve(to: CGPoint(x: br, y: bottom - r), control: CGPoint(x: br, y: bottom))
    p.addLine(to: CGPoint(x: br, y: 84))
    p.addCurve(to: CGPoint(x: nr, y: 44), control1: CGPoint(x: br, y: 58), control2: CGPoint(x: nr, y: 60))
    p.addLine(to: CGPoint(x: nr, y: 26))
    p.closeSubpath()
    return p
}

let s = rect.height * 0.70 / 220
var t = CGAffineTransform(translationX: rect.midX - 50 * s, y: rect.midY + 104 * s).scaledBy(x: s, y: -s)
let outer = bottle(0).copy(using: &t)!
let inner = bottle(3.2).copy(using: &t)!
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(t) }

// Glass body.
ctx.saveGState()
ctx.addPath(outer)
ctx.clip()
ctx.setFillColor(rgb(0xFFFFFF, 0.14))
ctx.fill(rect)
ctx.restoreGState()

// Water, with a wave on top.
let level: CGFloat = 112
let water = CGMutablePath()
water.move(to: pt(0, 230))
water.addLine(to: pt(0, level))
for i in 0...40 {
    let x = CGFloat(i) * 2.5
    water.addLine(to: pt(x, level + 3.2 * sin(x * 0.085 + 0.6) + 1.4 * sin(x * 0.19)))
}
water.addLine(to: pt(100, 230))
water.closeSubpath()
ctx.saveGState()
ctx.addPath(inner)
ctx.clip()
ctx.addPath(water)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x9CEBFF), rgb(0x2E9BFF), rgb(0x1238B8)], [0, 0.35, 1]),
                       start: pt(50, level - 6), end: pt(50, 218), options: [])
// Bubbles.
for (x, y, r) in [(34.0, 190.0, 3.4), (58.0, 168.0, 2.4), (44.0, 146.0, 2.0), (66.0, 198.0, 2.8), (52.0, 128.0, 1.6)] {
    let c = pt(x, y)
    let rr = r * s
    ctx.setFillColor(rgb(0xFFFFFF, 0.2))
    ctx.fillEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.7))
    ctx.setLineWidth(2.2)
    ctx.strokeEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
}
ctx.restoreGState()

// Meniscus line.
ctx.saveGState()
ctx.addPath(inner)
ctx.clip()
let line = CGMutablePath()
for i in 0...40 {
    let x = CGFloat(i) * 2.5
    let p = pt(x, level + 3.2 * sin(x * 0.085 + 0.6) + 1.4 * sin(x * 0.19))
    i == 0 ? line.move(to: p) : line.addLine(to: p)
}
ctx.addPath(line)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.9))
ctx.setLineWidth(6)
ctx.strokePath()
ctx.restoreGState()

// Highlights on the glass.
ctx.saveGState()
ctx.addPath(outer)
ctx.clip()
let band = CGRect(x: pt(13, 0).x, y: pt(0, 196).y, width: 7.5 * s, height: (196 - 92) * s)
ctx.addPath(CGPath(roundedRect: band, cornerWidth: band.width / 2, cornerHeight: band.width / 2, transform: nil))
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0), rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0.05)], [0, 0.45, 1]),
                       start: CGPoint(x: band.minX, y: 0), end: CGPoint(x: band.maxX, y: 0), options: [])
ctx.restoreGState()

// Outline.
ctx.addPath(outer)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.85))
ctx.setLineWidth(9)
ctx.strokePath()

// Cap.
let cap = CGRect(x: pt(31, 0).x, y: pt(0, 29).y, width: 38 * s, height: 26 * s)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: cap, cornerWidth: 5 * s, cornerHeight: 5 * s, transform: nil))
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xC9D6EA), rgb(0xFFFFFF), rgb(0xA9B9D3)], [0, 0.45, 1]),
                       start: CGPoint(x: cap.minX, y: 0), end: CGPoint(x: cap.maxX, y: 0), options: [])
ctx.setStrokeColor(rgb(0x7E8FB0, 0.6))
ctx.setLineWidth(4)
for i in 0..<9 {
    let x = cap.minX + (4 + CGFloat(i) * 3.75) * s
    ctx.move(to: CGPoint(x: x, y: cap.minY + 3 * s))
    ctx.addLine(to: CGPoint(x: x, y: cap.maxY - 6 * s))
}
ctx.strokePath()
ctx.restoreGState()

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "AppIcon.png") as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not write png")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote AppIcon.png (1024x1024)")
