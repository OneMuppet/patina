import AppKit

// Background for the install (.dmg) window. On-brand: ink field, copper arrow,
// "patina" wordmark. Rendered at 2× so it stays crisp on Retina.
// Logical window is 660×440; icons are placed by dmgbuild at the spots below.

let scale: CGFloat = 2
let LW: CGFloat = 660, LH: CGFloat = 440
let W = LW * scale, H = LH * scale

let ink = NSColor(srgbRed: 0.105, green: 0.10, blue: 0.088, alpha: 1)
let inkTop = NSColor(srgbRed: 0.13, green: 0.122, blue: 0.106, alpha: 1)
let paper = NSColor(srgbRed: 0.94, green: 0.91, blue: 0.84, alpha: 1)
let paperDim = NSColor(srgbRed: 0.66, green: 0.61, blue: 0.53, alpha: 1)
let copper = NSColor(srgbRed: 0.80, green: 0.47, blue: 0.18, alpha: 1)

// logical → pixel (CG bottom-left origin; flip Y from a top-left logical value)
func px(_ v: CGFloat) -> CGFloat { v * scale }
func cgY(_ topY: CGFloat) -> CGFloat { (LH - topY) * scale }   // top-left logical Y → CG pixel Y

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)     // draw in pixel space (2×)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background + subtle top sheen
NSGradient(colors: [inkTop, ink])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

// Strata glyph (small) top-left of the wordmark
func bar(_ x: CGFloat, _ topY: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
    c.setFill()
    NSBezierPath(roundedRect: NSRect(x: px(x), y: cgY(topY + h), width: px(w), height: px(h)),
                 xRadius: px(h/2), yRadius: px(h/2)).fill()
}
let gx: CGFloat = 232, gy: CGFloat = 54
bar(gx, gy,      34, 8, copper)
bar(gx, gy + 13, 22, 8, paper)
bar(gx, gy + 26, 29, 8, paper)

// Wordmark "patina"
let wm = NSAttributedString(string: "patina", attributes: [
    .font: NSFont.systemFont(ofSize: px(40), weight: .bold),
    .foregroundColor: paper,
    .kern: px(-1)])
let wmSize = wm.size()
wm.draw(at: NSPoint(x: px(286), y: cgY(96) - wmSize.height * 0.5))

// Copper arrow between the two icon spots (icons centered at logical y≈215)
let ay = cgY(215)
let ax0 = px(266), ax1 = px(398)
copper.setStroke()
let shaft = NSBezierPath()
shaft.lineWidth = px(5); shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: ax0, y: ay)); shaft.line(to: NSPoint(x: ax1 - px(10), y: ay))
shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: ax1, y: ay))
head.line(to: NSPoint(x: ax1 - px(16), y: ay + px(11)))
head.line(to: NSPoint(x: ax1 - px(16), y: ay - px(11)))
head.close(); copper.setFill(); head.fill()

// "drag to install" caption above the arrow
let cap = NSAttributedString(string: "drag to install", attributes: [
    .font: NSFont.systemFont(ofSize: px(14), weight: .medium),
    .foregroundColor: paperDim, .kern: px(0.5)])
let capSize = cap.size()
cap.draw(at: NSPoint(x: px(332) - capSize.width / 2, y: cgY(255)))

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/dmg-bg.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(Int(W))×\(Int(H)) px)")
