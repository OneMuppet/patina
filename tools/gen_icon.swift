import AppKit

// Patina icon generator — flat ink field, abstract marks in paper + one copper accent.
// Build:   gen_icon <mark> [outDir]
// Preview: gen_icon variant <mark> <outPath>   (single 512 PNG)

let ink = NSColor(srgbRed: 0.11, green: 0.105, blue: 0.09, alpha: 1)
let paper = NSColor(srgbRed: 0.94, green: 0.91, blue: 0.84, alpha: 1)
let copper = NSColor(srgbRed: 0.80, green: 0.47, blue: 0.18, alpha: 1)

func squircle(_ r: NSRect) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: r.width * 0.2237, yRadius: r.height * 0.2237) }
func rrect(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }

// MARK: marks (drawn within a centered box of side `m` at origin (ox,oy))

// Strata: stacked rounded bars — lines of text / layers of patina; bottom is copper.
func strata(_ S: CGFloat) {
    let m = S * 0.46, ox = (S - m) / 2, oy = (S - m) / 2
    let h = m * 0.135, gap = (m - h * 4) / 3
    let widths: [CGFloat] = [1.0, 0.72, 0.86, 0.45]
    for i in 0..<4 {
        let y = oy + CGFloat(3 - i) * (h + gap)
        let w = m * widths[i]
        (i == 0 ? copper : paper).setFill()
        rrect(NSRect(x: ox, y: y, width: w, height: h), h / 2).fill()
    }
}

// Layers: two offset rounded cards — notes stacking; the one beneath is copper.
func layers(_ S: CGFloat) {
    let side = S * 0.40, rad = S * 0.05, off = S * 0.085
    let cx = (S - side) / 2, cy = (S - side) / 2
    copper.setFill()
    rrect(NSRect(x: cx + off, y: cy - off, width: side, height: side), rad).fill()
    // knock out a gap so the paper card reads as separate
    ink.setFill()
    rrect(NSRect(x: cx - S*0.012, y: cy - S*0.012, width: side + S*0.024, height: side + S*0.024), rad + 2).fill()
    paper.setFill()
    rrect(NSRect(x: cx, y: cy, width: side, height: side), rad).fill()
}

// Tide: paper square, lower third is copper — the patina line on metal.
func tide(_ S: CGFloat) {
    let side = S * 0.46, rad = S * 0.07
    let x = (S - side) / 2, y = (S - side) / 2
    NSGraphicsContext.saveGraphicsState()
    rrect(NSRect(x: x, y: y, width: side, height: side), rad).addClip()
    paper.setFill(); NSRect(x: x, y: y, width: side, height: side).fill()
    copper.setFill(); NSRect(x: x, y: y, width: side, height: side * 0.34).fill()
    NSGraphicsContext.restoreGraphicsState()
}

// Ring: a paper ring with a copper core — oxidation spreading from a point.
func ring(_ S: CGFloat) {
    let d = S * 0.46, x = (S - d) / 2, y = (S - d) / 2
    let lw = S * 0.075
    paper.setStroke()
    let p = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: d, height: d))
    p.lineWidth = lw; p.stroke()
    let cd = S * 0.16
    copper.setFill()
    NSBezierPath(ovalIn: NSRect(x: (S - cd)/2, y: (S - cd)/2, width: cd, height: cd)).fill()
}

func draw(_ S: CGFloat, _ mark: String) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: S, height: S)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let margin = S * 0.085
    let rect = NSRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
    NSGraphicsContext.saveGraphicsState()
    squircle(rect).addClip()
    ink.setFill(); rect.fill()
    NSGradient(colors: [NSColor(white: 1, alpha: 0.05), NSColor(white: 1, alpha: 0)])!.draw(in: rect, angle: 90)
    NSGraphicsContext.restoreGraphicsState()
    switch mark {
    case "strata": strata(S)
    case "layers": layers(S)
    case "tide": tide(S)
    case "ring": ring(S)
    default: strata(S)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let args = CommandLine.arguments
if args.count >= 4, args[1] == "variant" {
    try! draw(512, args[2]).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
    print("variant \(args[2]) → \(args[3])")
} else {
    let mark = args.count >= 2 ? args[1] : "strata"
    let outDir = args.count >= 3 ? args[2] : "AppIcon.iconset"
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let specs: [(String, CGFloat)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
        ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (n, size) in specs {
        try! draw(size, mark).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(n).png"))
    }
    print("Wrote iconset (\(mark)) to \(outDir)")
}
