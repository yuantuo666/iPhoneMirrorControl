import AppKit
import CoreGraphics
import CoreText
import Foundation

public struct AnnotateOptions {
    public var drawGrid = true
    public var crosshair: (normX: Double, normY: Double)? = nil
    public var ocrHits: [OCRHit] = []
    public var drawOCRHits = false
    public var footer: String? = nil
    public init() {}
}

public enum Annotate {
    // Canvas margins in capture pixels (capture is 2x points).
    private static let leftMargin = 64
    private static let topMargin = 44
    private static let rightMargin = 12
    private static let bottomMargin = 14

    public static func render(frame: MirrorFrame, detection: DisplayDetection,
                              options: AnnotateOptions = AnnotateOptions()) -> CGImage? {
        let rect = detection.rect
        let crop = frame.bitmap.cropped(to: rect)
        let dw = crop.width, dh = crop.height
        let canvasW = leftMargin + dw + rightMargin
        let footerH = options.footer != nil ? 34 : 0
        let canvasH = topMargin + dh + bottomMargin + footerH
        guard let ctx = CGContext(data: nil, width: canvasW, height: canvasH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Light canvas.
        ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

        // Draw the phone display. Origin is bottom-left; image draws upright.
        let imageRect = CGRect(x: leftMargin, y: bottomMargin + footerH, width: dw, height: dh)
        if let img = crop.cgImage() {
            ctx.draw(img, in: imageRect)
        }

        // Border around the phone image.
        ctx.setStrokeColor(CGColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 0.45))
        ctx.setLineWidth(2)
        ctx.stroke(imageRect.insetBy(dx: -1, dy: -1))

        if options.drawGrid {
            drawGrid(ctx: ctx, imageRect: imageRect, canvasW: canvasW, canvasH: canvasH)
        }

        if options.drawOCRHits {
            drawOCRBoxes(ctx: ctx, imageRect: imageRect, hits: options.ocrHits)
        }

        if let ch = options.crosshair {
            let p = CGPoint(x: imageRect.minX + imageRect.width * ch.normX,
                            y: imageRect.minY + imageRect.height * (1 - ch.normY))
            drawCrosshair(ctx: ctx, at: p, label: String(format: "aim %.1f%%, %.1f%%", ch.normX * 100, ch.normY * 100))
        }

        if let footer = options.footer {
            drawText(footer, ctx: ctx, x: 14, baseline: 12 + 4, size: 16,
                     color: NSColor(calibratedWhite: 0.25, alpha: 1), anchor: .left)
        }

        return ctx.makeImage()
    }

    private static func drawGrid(ctx: CGContext, imageRect: CGRect, canvasW: Int, canvasH: Int) {
        let labelColor = NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.30, alpha: 1)
        let tickColor = NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.60, alpha: 1)
        let lineColor = CGColor(red: 1.0, green: 0.18, blue: 0.43, alpha: 0.38)

        for i in 0...50 { // minor ticks every 2%
            let t = Double(i) / 50.0
            let x = imageRect.minX + imageRect.width * t
            let y = imageRect.maxY - imageRect.height * t
            if i % 5 != 0 {
                ctx.setStrokeColor(tickColor.cgColor)
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: x, y: imageRect.maxY))
                ctx.addLine(to: CGPoint(x: x, y: imageRect.maxY - 5))
                ctx.strokePath()
                ctx.move(to: CGPoint(x: imageRect.minX, y: y))
                ctx.addLine(to: CGPoint(x: imageRect.minX + 5, y: y))
                ctx.strokePath()
            }
        }

        for i in 0...10 { // major lines every 10%; percentage measured from the top
            let t = Double(i) / 10.0
            let x = imageRect.minX + imageRect.width * t
            let y = imageRect.maxY - imageRect.height * t

            ctx.setStrokeColor(lineColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: x, y: imageRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: imageRect.maxY))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: imageRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: imageRect.maxX, y: y))
            ctx.strokePath()

            let pct = "\(i * 10)%"
            // Top ruler label centered on the line.
            drawText(pct, ctx: ctx, x: x, baseline: Double(imageRect.maxY) + 12, size: 17,
                     color: labelColor, anchor: .center)
            // Left ruler label right-aligned at the line.
            drawText(pct, ctx: ctx, x: Double(imageRect.minX) - 8, baseline: Double(y) - 6, size: 17,
                     color: labelColor, anchor: .right)
        }
    }

    private static func drawOCRBoxes(ctx: CGContext, imageRect: CGRect, hits: [OCRHit]) {
        ctx.setStrokeColor(CGColor(red: 0.0, green: 0.65, blue: 0.35, alpha: 0.9))
        ctx.setLineWidth(2)
        for h in hits {
            let r = CGRect(x: imageRect.minX + imageRect.width * h.x,
                           y: imageRect.minY + imageRect.height * (1 - h.y - h.h),
                           width: imageRect.width * h.w,
                           height: imageRect.height * h.h)
            ctx.stroke(r)
        }
    }

    private static func drawCrosshair(ctx: CGContext, at p: CGPoint, label: String) {
        let r: CGFloat = 24
        ctx.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.2, alpha: 0.18))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.2, alpha: 1))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: p.x - r - 14, y: p.y))
        ctx.addLine(to: CGPoint(x: p.x + r + 14, y: p.y))
        ctx.move(to: CGPoint(x: p.x, y: p.y - r - 14))
        ctx.addLine(to: CGPoint(x: p.x, y: p.y + r + 14))
        ctx.strokePath()

        // Label with a white pill background above the crosshair.
        let text = label
        let size: CGFloat = 16
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.8, green: 0.0, blue: 0.1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let pad: CGFloat = 6
        let bx = min(max(4, p.x - CGFloat(width) / 2 - pad), ctx.width == 0 ? p.x : CGFloat(ctx.width) - CGFloat(width) - 2 * pad - 4)
        let by = p.y + r + 10
        let box = CGRect(x: bx, y: by, width: CGFloat(width) + pad * 2, height: ascent + descent + 6)
        let path = CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setFillColor(CGColor(red: 0.8, green: 0, blue: 0.1, alpha: 1))
        ctx.textPosition = CGPoint(x: box.minX + pad, y: box.minY + descent + 3)
        CTLineDraw(line, ctx)
    }

    public enum TextAnchor { case left, center, right }

    private static func drawText(_ s: String, ctx: CGContext, x: Double, baseline: Double,
                                 size: CGFloat, color: NSColor, anchor: TextAnchor) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        var xx = x
        switch anchor {
        case .left: xx = x
        case .center: xx = x - Double(width) / 2
        case .right: xx = x - Double(width)
        }
        ctx.textPosition = CGPoint(x: xx, y: baseline)
        CTLineDraw(line, ctx)
    }
}
