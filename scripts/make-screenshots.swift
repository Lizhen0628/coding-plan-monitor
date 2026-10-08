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
    // 深色底衬，避免深色窗口圆角处透出白边
    NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1).setFill()
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
let panel = NSImage(contentsOfFile: "\(root)/images/panel.png")!
let panelExpand = NSImage(contentsOfFile: "\(root)/images/panel-expand.png")!
let settingsAccounts = NSImage(contentsOfFile: "\(root)/images/setting-remove-url.png")!
let settingsGeneral = NSImage(contentsOfFile: "\(root)/images/settings-general.png")!

// 素材本身已含菜单栏/桌面背景，直接居中加阴影贴到渐变画布上
func shot(_ img: NSImage, maxHeight: CGFloat = 720) -> NSImage {
    makeCanvas { _ in
        drawShadowed(img, in: centeredRect(fit: img.size, maxHeight: maxHeight))
    }
}

try? fm.createDirectory(atPath: "\(root)/images/appstore", withIntermediateDirectories: true)
savePNG(shot(panel), to: "\(root)/images/appstore/screenshot-1-panel.png")
savePNG(shot(panelExpand), to: "\(root)/images/appstore/screenshot-2-panel-expand.png")
savePNG(shot(settingsAccounts), to: "\(root)/images/appstore/screenshot-3-settings-accounts.png")
savePNG(shot(settingsGeneral), to: "\(root)/images/appstore/screenshot-4-settings-general.png")
