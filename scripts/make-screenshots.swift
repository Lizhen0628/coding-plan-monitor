#!/usr/bin/env swift
// 将菜单栏应用的截图合成到 1280×800 画布（App Store Connect macOS 截图要求尺寸）
// 用法: swift scripts/make-screenshots.swift
import AppKit

let canvasSize = NSSize(width: 1280, height: 800)

func makeCanvas(_ draw: (NSRect) -> Void) -> NSImage {
    let image = NSImage(size: canvasSize)
    image.lockFocus()
    // 深色渐变背景
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1),
        NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1),
    ])!
    gradient.draw(in: NSRect(origin: .zero, size: canvasSize), angle: -90)
    draw(NSRect(origin: .zero, size: canvasSize))
    image.unlockFocus()
    return image
}

func centeredRect(fit size: NSSize, maxHeight: CGFloat, yOffset: CGFloat = 0) -> NSRect {
    let scale = maxHeight / size.height
    let w = size.width * scale, h = maxHeight
    return NSRect(x: (canvasSize.width - w) / 2,
                  y: (canvasSize.height - h) / 2 + yOffset,
                  width: w, height: h)
}

func drawShadowed(_ img: NSImage, in rect: NSRect, radius: CGFloat = 18) {
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
    shadow.shadowBlurRadius = radius
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    img.draw(in: rect)
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("无法编码 PNG: \(path)")
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("✅ \(path)")
}

let fm = FileManager.default
let root = fm.currentDirectoryPath
let panel = NSImage(contentsOfFile: "\(root)/images/monitor panel.png")!
let settings = NSImage(contentsOfFile: "\(root)/images/settings.png")!
let menu = NSImage(contentsOfFile: "\(root)/images/menu.png")!

// 1. 菜单栏 + 监控面板
let shot1 = makeCanvas { canvas in
    // 顶部菜单栏条带，拉满画布宽度
    let menuH = menu.size.height * (canvas.width / menu.size.width)
    menu.draw(in: NSRect(x: 0, y: canvas.height - menuH, width: canvas.width, height: menuH))
    let rect = centeredRect(fit: panel.size, maxHeight: 700, yOffset: -20)
    drawShadowed(panel, in: rect)
}

// 2. 设置窗口
let shot2 = makeCanvas { _ in
    let rect = centeredRect(fit: settings.size, maxHeight: 700)
    drawShadowed(settings, in: rect)
}

// 3. 菜单栏状态特写（右侧 G:0% K:3% 区域放大）
let shot3 = makeCanvas { canvas in
    let cropW: CGFloat = 420
    let srcRect = NSRect(x: menu.size.width - cropW, y: 0, width: cropW, height: menu.size.height)
    let w: CGFloat = 900, h = w * (menu.size.height / cropW)
    let dest = NSRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = NSSize(width: 0, height: -4)
    shadow.set()
    NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.19, alpha: 1).setFill()
    NSBezierPath(roundedRect: dest.insetBy(dx: -30, dy: -30), xRadius: 16, yRadius: 16).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    menu.draw(in: dest, from: srcRect, operation: .sourceOver, fraction: 1)
}

try? fm.createDirectory(atPath: "\(root)/images/appstore", withIntermediateDirectories: true)
savePNG(shot1, to: "\(root)/images/appstore/screenshot-1-panel.png")
savePNG(shot2, to: "\(root)/images/appstore/screenshot-2-settings.png")
savePNG(shot3, to: "\(root)/images/appstore/screenshot-3-menubar.png")
