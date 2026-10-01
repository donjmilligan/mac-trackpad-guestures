// Generates the app icon set and the menu bar template image from Resources/AppIcon.png.
// Usage: swift scripts/make-icons.swift <source.png> <output-dir>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]) else {
    print("usage: make-icons.swift <source.png> <output-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: Int, artworkScale: CGFloat, transform: ((inout UInt8, inout UInt8, inout UInt8, inout UInt8) -> Void)? = nil) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let side = CGFloat(size) * artworkScale
    let inset = (CGFloat(size) - side) / 2
    source.draw(in: NSRect(x: inset, y: inset, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()

    if let transform, let data = rep.bitmapData {
        for i in stride(from: 0, to: rep.bytesPerRow * size, by: 4) {
            transform(&data[i], &data[i + 1], &data[i + 2], &data[i + 3])
        }
    }
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String, in dir: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
}

// App icon: macOS icon grid keeps artwork within ~824/1024 of the canvas.
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try write(render(size: base, artworkScale: 824 / 1024), "icon_\(base)x\(base).png", in: iconset)
    try write(render(size: base * 2, artworkScale: 824 / 1024), "icon_\(base)x\(base)@2x.png", in: iconset)
}

// Menu bar template: black, with opacity taken from how dark the logo is (white lines become transparent).
// Values are premultiplied, so black stays 0 and only alpha changes.
let template: (inout UInt8, inout UInt8, inout UInt8, inout UInt8) -> Void = { r, g, b, a in
    guard a > 0 else { return }
    let alpha = Double(a) / 255
    let luminance = (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255 / alpha
    a = UInt8(max(0, min(255, (1 - luminance) * alpha * 255)))
    r = 0; g = 0; b = 0
}
try write(render(size: 18, artworkScale: 1, transform: template), "MenuBarIcon.png", in: outDir)
try write(render(size: 36, artworkScale: 1, transform: template), "MenuBarIcon@2x.png", in: outDir)
