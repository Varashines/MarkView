import AppKit
import CoreGraphics

let iconSize: CGFloat = 1024
let image = NSImage(size: NSSize(width: iconSize, height: iconSize))

image.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// 1. Background — deep indigo gradient
let colors = [
    NSColor(red: 0.14, green: 0.18, blue: 0.35, alpha: 1.0).cgColor,
    NSColor(red: 0.22, green: 0.30, blue: 0.55, alpha: 1.0).cgColor
] as CFArray
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!

let bg = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210)
context.saveGState()
bg.addClip()
context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 40), end: CGPoint(x: 512, y: 984), options: [])
context.restoreGState()

// 2. Document — clean white page with subtle shadow
context.saveGState()
context.setShadow(offset: NSSize(width: 0, height: -8), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)

let docW: CGFloat = 500
let docH: CGFloat = 640
let docX = (iconSize - docW) / 2
let docY = (iconSize - docH) / 2 + 10

let docPath = NSBezierPath(roundedRect: NSRect(x: docX, y: docY, width: docW, height: docH), xRadius: 24, yRadius: 24)
NSColor.white.setFill()
docPath.fill()
context.restoreGState()

// 3. "M↓" markdown symbol — large, centered
let symbolAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 260),
    .foregroundColor: NSColor(red: 0.22, green: 0.30, blue: 0.55, alpha: 1.0)
]
let symbol = NSAttributedString(string: "M↓", attributes: symbolAttrs)
let symbolSize = symbol.size()
let symbolX = docX + (docW - symbolSize.width) / 2
let symbolY = docY + docH * 0.42
symbol.draw(at: NSPoint(x: symbolX, y: symbolY))

// 4. Horizontal lines (text placeholder)
let lineColor = NSColor(red: 0.22, green: 0.30, blue: 0.55, alpha: 0.15)
lineColor.setStroke()
context.setLineWidth(10)
context.setLineCap(.round)

let lineLeft = docX + 55
let lineRight = docX + docW - 55

let line1 = NSBezierPath()
line1.move(to: NSPoint(x: lineLeft, y: docY + 110))
line1.line(to: NSPoint(x: lineRight, y: docY + 110))
line1.stroke()

let line2 = NSBezierPath()
line2.move(to: NSPoint(x: lineLeft, y: docY + 70))
line2.line(to: NSPoint(x: lineRight - 80, y: docY + 70))
line2.stroke()

let line3 = NSBezierPath()
line3.move(to: NSPoint(x: lineLeft, y: docY + 30))
line3.line(to: NSPoint(x: lineRight - 160, y: docY + 30))
line3.stroke()

image.unlockFocus()

// 5. Save to iconset
let fileManager = FileManager.default
let iconsetPath = "AppIcon.iconset"
try? fileManager.removeItem(atPath: iconsetPath)
try? fileManager.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let resized = NSImage(size: NSSize(width: size, height: size))
    resized.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    resized.unlockFocus()

    if let tiff = resized.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
        let png = bitmap.representation(using: .png, properties: [:])
        let name = "icon_\(size)x\(size)"
        try? png?.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
        if size * 2 <= 1024 {
            try? png?.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)@2x.png"))
        }
    }
}

print("Generated AppIcon.iconset")
