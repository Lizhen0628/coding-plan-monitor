import AppKit

// 生成 App 图标：深空灰底 + 三色同心圆环（分别对应 5 小时 / 每周 / 每月额度）
// 用法: swift scripts/make-icon.swift [输出路径]
// 注意：在 Retina 屏幕上输出为 2048×2048，需再用 sips -z 1024 1024 缩到标准尺寸
let side: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

// 背景：圆角矩形 + 深空灰渐变
let inset: CGFloat = 80
let bgRect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 200, yRadius: 200)
NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1),
    NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.07, alpha: 1),
])!.draw(in: bgPath, angle: -90)

func ring(center: NSPoint, radius: CGFloat, width: CGFloat,
          color: NSColor, sweep: CGFloat, trackOnly: Bool = false) {
    let path = NSBezierPath()
    if trackOnly {
        path.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        NSColor.white.withAlphaComponent(0.12).setStroke()
    } else {
        // 从正上方（90°）顺时针扫 sweep 度
        path.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - sweep, clockwise: true)
        NSGraphicsContext.current?.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color.withAlphaComponent(0.55)
        glow.shadowBlurRadius = 28
        glow.set()
        color.setStroke()
    }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.stroke()
    if !trackOnly { NSGraphicsContext.current?.restoreGraphicsState() }
}

let center = NSPoint(x: side / 2, y: side / 2)
let specs: [(radius: CGFloat, color: NSColor, sweep: CGFloat)] = [
    (296, NSColor(calibratedRed: 0.25, green: 0.90, blue: 0.50, alpha: 1), 250), // 绿：5 小时
    (206, NSColor(calibratedRed: 0.35, green: 0.60, blue: 1.00, alpha: 1), 190), // 蓝：每周
    (116, NSColor(calibratedRed: 0.70, green: 0.45, blue: 1.00, alpha: 1), 300), // 紫：每月
]
for spec in specs {
    ring(center: center, radius: spec.radius, width: 52, color: spec.color, sweep: 0, trackOnly: true)
    ring(center: center, radius: spec.radius, width: 52, color: spec.color, sweep: spec.sweep)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("无法生成 PNG")
}
try png.write(to: URL(fileURLWithPath: output))
print("图标已生成: \(output)")
