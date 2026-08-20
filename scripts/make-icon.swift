import AppKit

// 生成 1024x1024 App 图标：深色圆角矩形底 + 仪表盘
let side = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

// 背景：圆角矩形 + 渐变
let inset: CGFloat = 80
let bgRect = NSRect(x: inset, y: inset, width: CGFloat(side) - inset * 2, height: CGFloat(side) - inset * 2)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 200, yRadius: 200)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.42, alpha: 1),
    NSColor(calibratedRed: 0.22, green: 0.42, blue: 0.95, alpha: 1),
])!
gradient.draw(in: bgPath, angle: -90)

let center = NSPoint(x: side / 2, y: side / 2 - 20)
let radius: CGFloat = 280

// 仪表盘外弧（背景轨道）
let track = NSBezierPath()
track.appendArc(withCenter: center, radius: radius, startAngle: 150, endAngle: 30, clockwise: true)
track.lineWidth = 56
track.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.25).setStroke()
track.stroke()

// 仪表盘亮弧（约 1/3 处，示意用量）
let arc = NSBezierPath()
arc.appendArc(withCenter: center, radius: radius, startAngle: 150, endAngle: 70, clockwise: true)
arc.lineWidth = 56
arc.lineCapStyle = .round
NSColor(calibratedRed: 0.30, green: 0.95, blue: 0.55, alpha: 1).setStroke()
arc.stroke()

// 指针（指向亮弧末端 70°）
let needleAngle = CGFloat(70) * .pi / 180
let tip = NSPoint(x: center.x + cos(needleAngle) * (radius - 90),
                  y: center.y + sin(needleAngle) * (radius - 90))
let needle = NSBezierPath()
needle.move(to: center)
needle.line(to: tip)
needle.lineWidth = 34
needle.lineCapStyle = .round
NSColor.white.setStroke()
needle.stroke()

// 中心圆点
let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68))
NSColor.white.setFill()
dot.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("无法生成 PNG")
}
try png.write(to: URL(fileURLWithPath: output))
print("图标已生成: \(output)")
