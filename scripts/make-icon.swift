// 앱 아이콘(AppIcon.icns)을 코드로 그린다: swift scripts/make-icon.swift Support/AppIcon.icns
import AppKit

let out = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }

    // 배경: macOS 아이콘 그리드(824/1024)에 맞춘 둥근 사각형
    let bg = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(red: 0.27, green: 0.33, blue: 0.95, alpha: 1),
               ending: NSColor(red: 0.07, green: 0.11, blue: 0.43, alpha: 1))!.draw(in: bg, angle: -90)

    func device(_ rect: NSRect, radius: CGFloat, screen: NSColor) {
        NSColor(white: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius * s, yRadius: radius * s).fill()
        let inset = rect.insetBy(dx: 14 * s, dy: 14 * s)
        screen.setFill()
        NSBezierPath(roundedRect: inset, xRadius: (radius - 10) * s, yRadius: (radius - 10) * s).fill()
        // 화면 속 표 줄무늬
        NSColor(white: 1, alpha: 0.55).setFill()
        var y = inset.maxY - 40 * s
        while y > inset.minY + 20 * s {
            NSBezierPath(roundedRect: NSRect(x: inset.minX + 18 * s, y: y, width: inset.width - 36 * s, height: 14 * s),
                         xRadius: 7 * s, yRadius: 7 * s).fill()
            y -= 34 * s
        }
    }
    device(r(190, 230, 400, 540), radius: 46, screen: NSColor(red: 0.98, green: 0.55, blue: 0.36, alpha: 1)) // 태블릿
    device(r(500, 200, 210, 420), radius: 40, screen: NSColor(red: 0.35, green: 0.85, blue: 0.75, alpha: 1)) // 폰
    device(r(650, 330, 180, 330), radius: 34, screen: NSColor(red: 1.0, green: 0.82, blue: 0.3, alpha: 1))  // 작은 폰

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out]
try! p.run(); p.waitUntilExit()
print("wrote \(out)")
