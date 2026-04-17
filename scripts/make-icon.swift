#!/usr/bin/env swift
//
//  make-icon.swift
//  Renders a 1024x1024 PNG for colay's AppIcon using Core Graphics.
//  Run:  swift scripts/make-icon.swift docs/icon.png
//

import AppKit
import CoreGraphics
import Foundation

let outPath = CommandLine.arguments.dropFirst().first ?? "docs/icon.png"
let size: CGFloat = 1024

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("ctx") }

// macOS app icon: 1024x1024 with ~100px inset for the rounded-square tile.
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius: CGFloat = tile.width * 0.2237 // Apple squircle approximation

// Background gradient — soft warm peach → deep coral, matches "procedural companion" vibe
let gradient = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 1.00, green: 0.78, blue: 0.55, alpha: 1),   // #FFC78C
        CGColor(red: 0.97, green: 0.47, blue: 0.42, alpha: 1),   // #F8786B
        CGColor(red: 0.72, green: 0.29, blue: 0.44, alpha: 1),   // #B84A70
    ] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!

ctx.saveGState()
let path = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path)
ctx.clip()
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: tile.minX, y: tile.maxY),
    end:   CGPoint(x: tile.maxX, y: tile.minY),
    options: []
)
ctx.restoreGState()

// Orbit arcs — two thin concentric ellipses suggesting a companion's path
ctx.saveGState()
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
ctx.setLineWidth(14)
let cx = tile.midX, cy = tile.midY
ctx.addEllipse(in: CGRect(x: cx - 300, y: cy - 180, width: 600, height: 360))
ctx.strokePath()
ctx.setLineWidth(8)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
ctx.addEllipse(in: CGRect(x: cx - 380, y: cy - 230, width: 760, height: 460))
ctx.strokePath()
ctx.restoreGState()

// The sprite — a plump "dot" character with two eyes, sitting slightly below center.
// White body with subtle shadow, charcoal eyes — reads well at 16x16 too.
let bodyRadius: CGFloat = 230
let bodyCenter = CGPoint(x: cx, y: cy - 20)
let bodyRect = CGRect(
    x: bodyCenter.x - bodyRadius,
    y: bodyCenter.y - bodyRadius,
    width: bodyRadius * 2,
    height: bodyRadius * 2
)

// Soft drop-shadow
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -16),
    blur: 36,
    color: CGColor(red: 0.25, green: 0.08, blue: 0.15, alpha: 0.35)
)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillEllipse(in: bodyRect)
ctx.restoreGState()

// Eyes
let eyeY = bodyCenter.y + 35
let eyeDX: CGFloat = 75
let eyeR: CGFloat = 36
ctx.setFillColor(CGColor(red: 0.15, green: 0.10, blue: 0.18, alpha: 1))
ctx.fillEllipse(in: CGRect(x: bodyCenter.x - eyeDX - eyeR, y: eyeY - eyeR, width: eyeR*2, height: eyeR*2))
ctx.fillEllipse(in: CGRect(x: bodyCenter.x + eyeDX - eyeR, y: eyeY - eyeR, width: eyeR*2, height: eyeR*2))

// Catchlight highlights
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: bodyCenter.x - eyeDX - 5, y: eyeY + 8, width: 16, height: 16))
ctx.fillEllipse(in: CGRect(x: bodyCenter.x + eyeDX - 5, y: eyeY + 8, width: 16, height: 16))

// Export PNG
guard let cg = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: cg)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
let url = URL(fileURLWithPath: outPath)
try! png.write(to: url)
print("wrote \(outPath) \(Int(size))x\(Int(size))")
