#!/usr/bin/env swift
//
//  make-dmg-bg.swift
//  Renders a 540x380 @2x background PNG for the installer DMG window.
//  Run:  swift scripts/make-dmg-bg.swift docs/dmg-background.png
//

import AppKit
import CoreGraphics
import Foundation

let outPath = CommandLine.arguments.dropFirst().first ?? "docs/dmg-background.png"
let W: CGFloat = 540, H: CGFloat = 380
let scale: CGFloat = 2
let pxW = Int(W * scale), pxH = Int(H * scale)

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: pxW, height: pxH,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("ctx") }
ctx.scaleBy(x: scale, y: scale)

// Soft vertical gradient matching the app icon palette (muted)
let gradient = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 1.00, green: 0.96, blue: 0.92, alpha: 1),
        CGColor(red: 0.99, green: 0.89, blue: 0.83, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient, start: .init(x: 0, y: H), end: .init(x: 0, y: 0), options: [])

// Title
let title = "Install colay"
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.15, blue: 0.22, alpha: 1)
]
let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
let tsz = titleStr.size()
let flipped = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = flipped
titleStr.draw(at: .init(x: (W - tsz.width) / 2, y: H - 54))

let subtitle = "Drag the app into your Applications folder"
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.30, alpha: 0.85)
]
let subStr = NSAttributedString(string: subtitle, attributes: subAttrs)
let ssz = subStr.size()
subStr.draw(at: .init(x: (W - ssz.width) / 2, y: H - 82))
NSGraphicsContext.restoreGraphicsState()

// Arrow from app slot (left, centered around x=135, y=185) to /Applications (right, x=405, y=185)
// Icon slots are 128x128; arrow should sit between them.
ctx.saveGState()
ctx.setStrokeColor(CGColor(red: 0.72, green: 0.29, blue: 0.44, alpha: 0.75))
ctx.setFillColor(CGColor(red: 0.72, green: 0.29, blue: 0.44, alpha: 0.75))
ctx.setLineWidth(4)
ctx.setLineCap(.round)

let y: CGFloat = 180
let x1: CGFloat = 215, x2: CGFloat = 325
ctx.move(to: .init(x: x1, y: y))
ctx.addLine(to: .init(x: x2 - 12, y: y))
ctx.strokePath()

// arrowhead
ctx.move(to: .init(x: x2, y: y))
ctx.addLine(to: .init(x: x2 - 18, y: y + 10))
ctx.addLine(to: .init(x: x2 - 18, y: y - 10))
ctx.closePath()
ctx.fillPath()
ctx.restoreGState()

// Export
guard let cg = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: cg)
rep.size = NSSize(width: W, height: H) // Preserves @2x metadata
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) \(pxW)x\(pxH)")
