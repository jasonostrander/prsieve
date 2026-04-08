#!/usr/bin/env swift
// Generates AppIcon.icns using CoreGraphics (no external dependencies)
import AppKit
import Foundation

let size = 1024.0

func drawIcon(in ctx: CGContext) {
    let s = size

    // --- Colors ---
    let bgTop = NSColor(red: 0.231, green: 0.302, blue: 0.420, alpha: 1)      // #3B4D6B
    let bgBottom = NSColor(red: 0.118, green: 0.165, blue: 0.243, alpha: 1)    // #1E2A3E
    let funnelTop = NSColor(red: 0.831, green: 0.584, blue: 0.416, alpha: 1)   // #D4956A
    let funnelBottom = NSColor(red: 0.769, green: 0.471, blue: 0.251, alpha: 1) // #C47840
    let rimColor = NSColor(red: 0.910, green: 0.722, blue: 0.541, alpha: 0.6)  // #E8B88A
    let amber = NSColor(red: 0.910, green: 0.651, blue: 0.333, alpha: 1)       // #E8A655
    let slateBlue = NSColor(red: 0.478, green: 0.620, blue: 0.761, alpha: 1)   // #7A9EC2
    let gray = NSColor(red: 0.541, green: 0.541, blue: 0.557, alpha: 1)        // #8A8A8E
    let holeColor = NSColor(red: 0.118, green: 0.165, blue: 0.243, alpha: 0.4)

    // --- Rounded rect clip (macOS icon shape) ---
    let cornerRadius = s * 0.223  // ~228/1024
    let iconRect = CGRect(x: 0, y: 0, width: s, height: s)
    let iconPath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(iconPath)
    ctx.clip()

    // --- Background gradient ---
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: colorSpace,
                                  colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray,
                                  locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])
    }

    // --- Subtle grid lines ---
    ctx.setStrokeColor(NSColor(red: 0.29, green: 0.376, blue: 0.502, alpha: 0.15).cgColor)
    ctx.setLineWidth(1)
    for x in [200.0, 350, 500, 650, 824] {
        let sx = x / 1024 * s
        ctx.move(to: CGPoint(x: sx, y: 0))
        ctx.addLine(to: CGPoint(x: sx, y: s))
    }
    for y in [200.0, 350, 500, 650, 824] {
        let sy = y / 1024 * s
        ctx.move(to: CGPoint(x: 0, y: sy))
        ctx.addLine(to: CGPoint(x: s, y: sy))
    }
    ctx.strokePath()

    // --- Helper to map from 1024-space to actual size ---
    func p(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x / 1024 * s, y: (1024 - y) / 1024 * s)  // flip Y for CG
    }
    func sz(_ v: Double) -> Double { v / 1024 * s }

    // --- Funnel shape ---
    ctx.saveGState()
    let funnelPath = CGMutablePath()
    funnelPath.move(to: p(204, 280))
    funnelPath.addLine(to: p(820, 280))
    funnelPath.addLine(to: p(820, 340))
    funnelPath.addLine(to: p(580, 580))
    funnelPath.addLine(to: p(580, 740))
    funnelPath.addLine(to: p(620, 800))
    funnelPath.addLine(to: p(512, 850))
    funnelPath.addLine(to: p(404, 800))
    funnelPath.addLine(to: p(444, 740))
    funnelPath.addLine(to: p(444, 580))
    funnelPath.addLine(to: p(204, 340))
    funnelPath.closeSubpath()

    ctx.addPath(funnelPath)
    ctx.clip()

    if let fGrad = CGGradient(colorsSpace: colorSpace,
                               colors: [funnelTop.cgColor, funnelBottom.cgColor] as CFArray,
                               locations: [0, 1]) {
        ctx.drawLinearGradient(fGrad, start: p(512, 280), end: p(512, 850), options: [])
    }
    ctx.restoreGState()

    // --- Funnel rim highlight ---
    ctx.setFillColor(rimColor.cgColor)
    let rimRect = CGRect(x: sz(204), y: (1024 - 287) / 1024 * s, width: sz(616), height: sz(12))
    ctx.fill(rimRect)

    // --- Sieve holes ---
    ctx.setFillColor(holeColor.cgColor)
    let holes: [(Double, Double, Double)] = [
        (350, 340, 14), (420, 340, 14), (490, 340, 14), (560, 340, 14), (680, 340, 14),
        (310, 390, 12), (380, 395, 12), (450, 400, 12), (520, 400, 12), (590, 395, 12), (660, 390, 12),
        (420, 450, 10), (490, 455, 10), (560, 450, 10),
    ]
    for (hx, hy, hr) in holes {
        let center = p(hx, hy)
        let r = sz(hr)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    // --- Three dots (priority, low, noise) above funnel ---
    let dots: [(Double, Double, Double, NSColor)] = [
        (360, 180, 28, amber),
        (512, 155, 28, slateBlue),
        (664, 180, 28, gray),
    ]
    for (dx, dy, dr, color) in dots {
        let center = p(dx, dy)
        let r = sz(dr)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        // Inner dot
        let ir = sz(12)
        ctx.setFillColor(holeColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - ir, y: center.y - ir, width: ir * 2, height: ir * 2))
    }

    // --- Flow lines from dots to funnel ---
    ctx.setLineWidth(sz(4))
    ctx.setLineCap(.round)

    // Amber flow (left dot)
    ctx.setStrokeColor(amber.withAlphaComponent(0.5).cgColor)
    ctx.move(to: p(360, 208))
    ctx.addQuadCurve(to: p(400, 260), control: p(360, 244))
    ctx.strokePath()

    // Blue flow (center dot)
    ctx.setStrokeColor(slateBlue.withAlphaComponent(0.5).cgColor)
    ctx.move(to: p(512, 183))
    ctx.addLine(to: p(512, 258))
    ctx.strokePath()

    // Gray flow (right dot)
    ctx.setStrokeColor(gray.withAlphaComponent(0.5).cgColor)
    ctx.move(to: p(664, 208))
    ctx.addQuadCurve(to: p(624, 260), control: p(664, 244))
    ctx.strokePath()

    // --- Output arrow below funnel ---
    ctx.setStrokeColor(amber.withAlphaComponent(0.8).cgColor)
    ctx.setLineWidth(sz(8))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Vertical line
    ctx.move(to: p(512, 850))
    ctx.addLine(to: p(512, 920))
    ctx.strokePath()

    // Arrow head
    ctx.move(to: p(490, 900))
    ctx.addLine(to: p(512, 930))
    ctx.addLine(to: p(534, 900))
    ctx.strokePath()
}

// --- Render to PNG ---
func renderPNG(size: Int) -> Data? {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: size, pixelsHigh: size,
                                bitsPerSample: 8, samplesPerPixel: 4,
                                hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cgCtx = ctx.cgContext
    cgCtx.scaleBy(x: Double(size) / 1024.0, y: Double(size) / 1024.0)
    drawIcon(in: cgCtx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// --- Generate iconset ---
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let iconsetDir = "\(scriptDir)/AppIcon.iconset"
let icnsPath = "\(scriptDir)/AppIcon.icns"

let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for (name, sz) in sizes {
    guard let pngData = renderPNG(size: sz) else {
        print("Failed to render \(name)")
        exit(1)
    }
    let path = "\(iconsetDir)/\(name).png"
    try pngData.write(to: URL(fileURLWithPath: path))
    print("  Generated \(name).png (\(sz)x\(sz))")
}

// Convert to icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    try? fm.removeItem(atPath: iconsetDir)
    print("Created: \(icnsPath)")
} else {
    print("iconutil failed with status \(task.terminationStatus)")
    exit(1)
}
