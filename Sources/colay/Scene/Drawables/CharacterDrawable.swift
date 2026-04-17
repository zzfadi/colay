import AppKit
import CoreGraphics
import Foundation

/// Procedural character with:
/// - soft shadow (sells depth above the desktop)
/// - breathing body (scale wobble driven by `time`)
/// - organic squircle shape
/// - glowing floating sensors/antennae
/// - saccading eyes that look toward `lookTarget` (in node-local coords)
/// - periodic blink
final class CharacterDrawable: Drawable {
    var body: NSColor = NSColor(calibratedRed: 0.38, green: 0.78, blue: 1.00, alpha: 1)
    var bodyDark: NSColor = NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.56, alpha: 1)
    var outline: NSColor = NSColor(calibratedRed: 0.07, green: 0.15, blue: 0.28, alpha: 1)
    var eye: NSColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.12, alpha: 1)
    var highlight: NSColor = NSColor(calibratedWhite: 1.0, alpha: 0.85)

    /// Where the eyes should look, in the node's local coords.
    var lookTarget: CGPoint = CGPoint(x: 0, y: 60)

    /// If >0, overrides breathing scale with a hop (used by HopCommand).
    var hopPhase: Double = 0

    /// If >0 (up to 1), stretches the character into a thin vertical beam (for dive/emerge).
    var warpPhase: Double = 0

    func draw(in ctx: CGContext, size: CGSize, time: TimeInterval) {
        let w = max(size.width, 48)
        let h = max(size.height, 48)

        // Breathing: subtle vertical scale oscillation.
        let breath = 1.0 + 0.04 * sin(time * 1.6)
        let hop = hopPhase > 0 ? (1.0 + 0.15 * sin(hopPhase * .pi)) : 1.0
        
        let warp = CGFloat(warpPhase)
        let sy = breath * hop * (1.0 + warp * 1.5) // stretch vertically up to 2.5x
        let sx = 1.0 - warp * 0.8 // squish horizontally down to 0.2x
        
        // --- Shadow ---
        let shadowW = w * 0.85 * sx
        let shadowH = h * 0.25 * (1.0 - warp * 0.5)
        let lift = hopPhase > 0 ? sin(hopPhase * .pi) * h * 0.15 : 0
        // When warping, it sinks into the floor.
        let sink = warp * h * 0.4
        let shadowRect = CGRect(x: -shadowW/2, y: -h/2 - shadowH/2 - lift * 0.2 + sink, width: shadowW, height: shadowH)
        ctx.saveGState()
        
        let shadowAlpha = (0.15 - (lift / h * 0.05)) * (1.0 - warp)
        ctx.setFillColor(CGColor(gray: 0, alpha: max(0.0, shadowAlpha))) // lighter, softer shadow
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 10 + lift * 0.5, color: CGColor(gray: 0, alpha: max(0.0, 0.25 - lift/h*0.1 - warp*0.25)))
        ctx.fillEllipse(in: shadowRect)
        ctx.restoreGState()

        // --- Body with vertical gradient ---
        ctx.saveGState()
        // Squish origin is at the bottom (-h/2), lift it up if hopping, sink if warping
        ctx.translateBy(x: 0, y: -h/2 + lift + sink)
        ctx.scaleBy(x: sx, y: CGFloat(sy))
        ctx.translateBy(x: 0, y: h/2)
        
        let bodyRect = CGRect(x: -w/2, y: -h/2, width: w, height: h)
        
        // Create a more organic "squircle" path instead of a perfect circle
        let corner = min(w, h) * 0.45
        let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        
        let cs = CGColorSpaceCreateDeviceRGB()
        let grad = CGGradient(colorsSpace: cs,
                              colors: [body.cgColor, bodyDark.cgColor] as CFArray,
                              locations: [0, 1])!
        
        // Draw little "sensing" floaters/antennae that pop from it
        let sensorPhase = time * 3.0
        let leftSensor = CGPoint(x: -w * 0.25, y: h/2 + 8 + sin(sensorPhase) * 3)
        let rightSensor = CGPoint(x: w * 0.25, y: h/2 + 8 + cos(sensorPhase * 1.2) * 3)
        
        // Link to the body
        ctx.setStrokeColor(bodyDark.cgColor)
        ctx.setLineWidth(1.5)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: -w * 0.2, y: h/2 - corner*0.5))
        ctx.addCurve(to: leftSensor, control1: CGPoint(x: -w * 0.3, y: h/2), control2: CGPoint(x: -w * 0.25, y: leftSensor.y - 2))
        ctx.move(to: CGPoint(x: w * 0.2, y: h/2 - corner*0.5))
        ctx.addCurve(to: rightSensor, control1: CGPoint(x: w * 0.3, y: h/2), control2: CGPoint(x: w * 0.25, y: rightSensor.y - 2))
        ctx.strokePath()
        
        // Draw the floaters
        ctx.setFillColor(NSColor.cyan.cgColor)
        ctx.setShadow(offset: .zero, blur: 5, color: NSColor.cyan.cgColor)
        let sensorSize: CGFloat = 4.0 + sin(time * 5.0) * 1.5
        ctx.fillEllipse(in: CGRect(x: leftSensor.x - sensorSize/2, y: leftSensor.y - sensorSize/2, width: sensorSize, height: sensorSize))
        let sensorSize2: CGFloat = 4.0 + cos(time * 4.5) * 1.5
        ctx.fillEllipse(in: CGRect(x: rightSensor.x - sensorSize2/2, y: rightSensor.y - sensorSize2/2, width: sensorSize2, height: sensorSize2))
        ctx.setShadow(offset: .zero, blur: 0, color: nil) // Reset shadow

        ctx.addPath(bodyPath)
        ctx.clip()
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: 0, y: bodyRect.maxY),
                               end: CGPoint(x: 0, y: bodyRect.minY),
                               options: [])
        ctx.resetClip()
        ctx.setStrokeColor(outline.cgColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(bodyPath)
        ctx.strokePath()

        // Top gloss highlight
        ctx.setFillColor(highlight.cgColor)
        let glossW = w * 0.5
        let glossH = h * 0.15
        let glossPath = CGPath(roundedRect: CGRect(x: -glossW/2, y: h/2 - glossH - 6, width: glossW, height: glossH), cornerWidth: glossH/2, cornerHeight: glossH/2, transform: nil)
        ctx.addPath(glossPath)
        ctx.fillPath()
        ctx.restoreGState()

        // --- Eyes ---
        let blink = blinkAmount(time: time)
        let eyeY = h * 0.08 + lift
        let eyeDX = w * 0.23
        let eyeR = w * 0.1
        // Pupil offset towards lookTarget, clamped so it stays in the eye.
        let look = CGPoint(x: lookTarget.x, y: lookTarget.y).truncated(max: 1000).normalized()
        let pupilOff = CGPoint(x: look.x * eyeR * 0.45, y: look.y * eyeR * 0.45)

        drawEye(ctx, center: CGPoint(x: -eyeDX, y: eyeY), radius: eyeR, pupilOff: pupilOff, blink: blink)
        drawEye(ctx, center: CGPoint(x:  eyeDX, y: eyeY), radius: eyeR, pupilOff: pupilOff, blink: blink)
    }

    private func drawEye(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                         pupilOff: CGPoint, blink: CGFloat) {
        // White of eye
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        let h = radius * 2 * max(blink, 0.05)
        let rect = CGRect(x: center.x - radius, y: center.y - h/2, width: radius*2, height: h)
        ctx.fillEllipse(in: rect)
        
        // Pupil
        ctx.setFillColor(eye.cgColor)
        let pr = radius * 0.55
        let pupilRect = CGRect(
            x: center.x + pupilOff.x - pr,
            y: center.y + pupilOff.y * max(blink, 0.05) - pr * max(blink, 0.05),
            width: pr*2, height: pr*2 * max(blink, 0.05)
        )
        ctx.fillEllipse(in: pupilRect)
        
        // Catchlight
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        let cl = CGRect(
            x: center.x + pupilOff.x - pr*0.35,
            y: center.y + pupilOff.y + pr*0.15,
            width: pr*0.4, height: pr*0.4 * max(blink, 0.05)
        )
        ctx.fillEllipse(in: cl)
    }

    private func blinkAmount(time: TimeInterval) -> CGFloat {
        let period = 4.2
        let dur = 0.14
        let t = time.truncatingRemainder(dividingBy: period)
        if t < dur {
            let u = t / dur
            // 1 -> 0 -> 1 (closed in middle)
            return CGFloat(abs(u - 0.5) * 2)
        }
        return 1.0
    }
}
