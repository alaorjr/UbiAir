#!/usr/bin/env swift
import AppKit
import CoreGraphics
import ImageIO
import Foundation

// Original provisional UbiAir artwork rendered as standard macOS icon PNGs.
let outputDirectory = CommandLine.arguments.dropFirst().first ?? "Resources/Assets.xcassets/AppIcon.appiconset"
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let canvas = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}

func renderIcon() -> CGImage {
    let context = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let tile = CGRect(x: 44, y: 44, width: 936, height: 936)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: 220, cornerHeight: 220, transform: nil))
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace,
                              colors: [color(0.035, 0.30, 0.74), color(0.00, 0.70, 0.84)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 900), end: CGPoint(x: 930, y: 120), options: [])

    // Three flowing air ribbons.
    context.setStrokeColor(color(0.70, 0.96, 1, 0.48))
    context.setLineWidth(38)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for offset: CGFloat in [-1, 0, 1] {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 225, y: 680 + offset * 108))
        path.addCurve(to: CGPoint(x: 490, y: 545 + offset * 42),
                      control1: CGPoint(x: 340, y: 690 + offset * 75),
                      control2: CGPoint(x: 365, y: 560 + offset * 35))
        context.addPath(path)
        context.strokePath()
    }

    // Six-armed snow/air-flow glyph made only from original geometry.
    let center = CGPoint(x: 602, y: 507)
    context.setStrokeColor(color(1, 1, 1, 0.96))
    context.setLineWidth(38)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for index in 0..<3 {
        let angle = CGFloat(index) * .pi / 3
        let dx = cos(angle), dy = sin(angle)
        context.move(to: CGPoint(x: center.x - dx * 165, y: center.y - dy * 165))
        context.addLine(to: CGPoint(x: center.x + dx * 165, y: center.y + dy * 165))
    }
    for index in 0..<6 {
        let angle = CGFloat(index) * .pi / 3
        let tip = CGPoint(x: center.x + cos(angle) * 165, y: center.y + sin(angle) * 165)
        for branchOffset: CGFloat in [-1, 1] {
            let branchAngle = angle + .pi + branchOffset * .pi / 4
            context.move(to: tip)
            context.addLine(to: CGPoint(x: tip.x + cos(branchAngle) * 62,
                                        y: tip.y + sin(branchAngle) * 62))
        }
    }
    context.strokePath()
    context.setFillColor(color(1, 1, 1, 0.96))
    context.fillEllipse(in: CGRect(x: center.x - 25, y: center.y - 25, width: 50, height: 50))
    return context.makeImage()!
}

let source = renderIcon()
for (name, pixels) in sizes {
    let bitmap = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                           bytesPerRow: 0, space: colorSpace,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.interpolationQuality = .high
    bitmap.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let destination = CGImageDestinationCreateWithURL(outputURL.appendingPathComponent(name) as CFURL,
                                                       "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Failed to write \(name)") }
}
print("Wrote \(sizes.count) PNG icons to \(outputURL.path)")
