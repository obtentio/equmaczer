import AppKit
import Foundation

// Renders resources/AppIcon.svg into .build/AppIcon.icns using only
// stock macOS frameworks (ImageIO reads SVG). Build-asset helper for
// machines without librsvg; bundle.sh's own icon step stays canonical
// where rsvg-convert exists.

let root = CommandLine.arguments[1]
let svgPath = "\(root)/resources/AppIcon.svg"
let iconsetPath = "\(root)/.build/AppIcon.iconset"
let icnsPath = "\(root)/.build/AppIcon.icns"

guard let image = NSImage(contentsOfFile: svgPath) else {
    FileHandle.standardError.write("Failed to load SVG at \(svgPath)\n".data(using: .utf8)!)
    exit(1)
}

let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func pngData(for image: NSImage, pixels: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    rep?.size = NSSize(width: pixels, height: pixels)
    guard let rep else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for size in [16, 32, 128, 256, 512] {
    for (suffix, pixels) in [("", size), ("@2x", size * 2)] {
        guard let data = pngData(for: image, pixels: pixels) else {
            FileHandle.standardError.write("Render failed at \(pixels)px\n".data(using: .utf8)!)
            exit(1)
        }
        try data.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(size)x\(size)\(suffix).png"))
    }
}
print("Icon set rendered to \(iconsetPath)")
