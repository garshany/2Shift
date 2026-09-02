import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = root.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

struct IconSize {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String {
        scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    }
}

let sizes = [
    IconSize(points: 16, scale: 1),
    IconSize(points: 16, scale: 2),
    IconSize(points: 32, scale: 1),
    IconSize(points: 32, scale: 2),
    IconSize(points: 128, scale: 1),
    IconSize(points: 128, scale: 2),
    IconSize(points: 256, scale: 1),
    IconSize(points: 256, scale: 2),
    IconSize(points: 512, scale: 1),
    IconSize(points: 512, scale: 2)
]

func drawIcon(size: Int) throws -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let cornerRadius = CGFloat(size) * 0.22
    let background = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size) * 0.04, dy: CGFloat(size) * 0.04), xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.13, alpha: 1).setFill()
    background.fill()

    let accentRect = NSRect(x: CGFloat(size) * 0.12, y: CGFloat(size) * 0.58, width: CGFloat(size) * 0.76, height: CGFloat(size) * 0.18)
    let accent = NSBezierPath(roundedRect: accentRect, xRadius: CGFloat(size) * 0.07, yRadius: CGFloat(size) * 0.07)
    NSColor(calibratedRed: 0.13, green: 0.75, blue: 0.78, alpha: 1).setFill()
    accent.fill()

    let text = "2⇧"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let fontSize = CGFloat(size) * 0.38
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]

    let textRect = NSRect(x: 0, y: CGFloat(size) * 0.19, width: CGFloat(size), height: CGFloat(size) * 0.46)
    text.draw(in: textRect, withAttributes: attributes)

    let smallText = "RU"
    let smallAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: CGFloat(size) * 0.12, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.13, green: 0.75, blue: 0.78, alpha: 1),
        .paragraphStyle: paragraph
    ]
    let smallRect = NSRect(x: 0, y: CGFloat(size) * 0.11, width: CGFloat(size), height: CGFloat(size) * 0.18)
    smallText.draw(in: smallRect, withAttributes: smallAttributes)

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "TwoShiftIcon", code: 1)
    }

    return png
}

for iconSize in sizes {
    let data = try drawIcon(size: iconSize.pixels)
    try data.write(to: iconsetURL.appendingPathComponent(iconSize.filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "TwoShiftIcon", code: Int(process.terminationStatus))
}

print(icnsURL.path)
