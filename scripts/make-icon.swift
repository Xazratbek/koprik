// Draws Ko'prik's app icon: a suspension bridge on a deep blue-to-teal field.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// macOS icons sit on a rounded square inset from the canvas edge.
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
context.addPath(shape)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(shape)
context.clip()
let colors = [
    NSColor(red: 0.10, green: 0.16, blue: 0.42, alpha: 1).cgColor,
    NSColor(red: 0.13, green: 0.42, blue: 0.78, alpha: 1).cgColor,
    NSColor(red: 0.18, green: 0.78, blue: 0.80, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

// Water: a soft darker band along the bottom.
context.setFillColor(NSColor(red: 0.05, green: 0.10, blue: 0.30, alpha: 0.35).cgColor)
context.fill(CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: 210))

let white = NSColor.white.cgColor
context.setStrokeColor(white)
context.setFillColor(white)
context.setLineCap(.round)

let deckY: CGFloat = 400
let left = tile.minX + 70, right = tile.maxX - 70
let towerA: CGFloat = 370, towerB: CGFloat = 654
let towerTop: CGFloat = 720

// Deck.
context.setLineWidth(34)
context.move(to: CGPoint(x: left, y: deckY))
context.addLine(to: CGPoint(x: right, y: deckY))
context.strokePath()

// Towers.
context.setLineWidth(40)
for x in [towerA, towerB] {
    context.move(to: CGPoint(x: x, y: 300))
    context.addLine(to: CGPoint(x: x, y: towerTop))
    context.strokePath()
}

// Main cables: side spans and the centre span.
context.setLineWidth(18)
func cable(from start: CGPoint, to end: CGPoint, sag: CGFloat) -> (CGFloat) -> CGPoint {
    let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - sag)
    context.move(to: start)
    context.addQuadCurve(to: end, control: control)
    context.strokePath()
    return { t in
        let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
        return CGPoint(x: a * start.x + b * control.x + c * end.x, y: a * start.y + b * control.y + c * end.y)
    }
}
let centre = cable(from: CGPoint(x: towerA, y: towerTop), to: CGPoint(x: towerB, y: towerTop), sag: 250)
let leftSpan = cable(from: CGPoint(x: left, y: deckY + 20), to: CGPoint(x: towerA, y: towerTop), sag: -60)
let rightSpan = cable(from: CGPoint(x: towerB, y: towerTop), to: CGPoint(x: right, y: deckY + 20), sag: -60)

// Hangers from the cables down to the deck.
context.setLineWidth(9)
for curve in [centre, leftSpan, rightSpan] {
    for step in 1...4 {
        let point = curve(CGFloat(step) / 5)
        guard point.y > deckY + 30 else { continue }
        context.move(to: point)
        context.addLine(to: CGPoint(x: point.x, y: deckY))
        context.strokePath()
    }
}
context.restoreGState()
image.unlockFocus()

let tiff = image.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: output))
