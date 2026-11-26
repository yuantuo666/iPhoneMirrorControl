import CoreGraphics
import Foundation

public struct DisplayDetection {
    public let rect: CGRect          // pixels in the raw window capture, top-left origin
    public let confidence: Double
    public let method: String        // "detected", "calibration"
}

public struct Calibration: Codable {
    public var windowWidth: Double
    public var windowHeight: Double
    public var imageWidth: Int
    public var imageHeight: Int
    public var displayX: Double
    public var displayY: Double
    public var displayW: Double
    public var displayH: Double
    public var aspect: Double
    public var savedAt: String

    public init(windowWidth: Double, windowHeight: Double,
                imageWidth: Int, imageHeight: Int,
                displayX: Double, displayY: Double,
                displayW: Double, displayH: Double,
                aspect: Double, savedAt: String) {
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.displayX = displayX
        self.displayY = displayY
        self.displayW = displayW
        self.displayH = displayH
        self.aspect = aspect
        self.savedAt = savedAt
    }

    public var normalizedRect: CGRect {
        CGRect(x: displayX / Double(imageWidth),
               y: displayY / Double(imageHeight),
               width: displayW / Double(imageWidth),
               height: displayH / Double(imageHeight))
    }
}

public enum Display {
    public static func loadCalibration() -> Calibration? {
        guard let data = try? Data(contentsOf: Paths.calibrationFile),
              let c = try? JSONDecoder().decode(Calibration.self, from: data) else { return nil }
        return c
    }

    public static func saveCalibration(_ c: Calibration) {
        Paths.ensureDirectories()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(c) {
            try? data.write(to: Paths.calibrationFile)
        }
    }

    /// Locate the mirrored iPhone display inside the window capture.
    /// The window background is black/transparent; the display is a large rounded rectangle.
    public static func detect(in bmp: Bitmap) -> DisplayDetection? {
        let w = bmp.width, h = bmp.height
        guard w > 100, h > 200 else { return nil }

        // --- Column profile over the middle band (avoids toolbar / rounded corners).
        var colFrac = [Double](repeating: 0, count: w)
        var maxColFrac = 0.0
        let yStart = Int(Double(h) * 0.15), yEnd = Int(Double(h) * 0.85)
        let yStep = max(1, (yEnd - yStart) / 200)
        let yIndices = Array(stride(from: yStart, to: yEnd, by: yStep))
        for x in 0..<w {
            var n = 0
            for y in yIndices where !bmp.isBackground(x: x, y: y) { n += 1 }
            colFrac[x] = Double(n) / Double(max(1, yIndices.count))
            maxColFrac = max(maxColFrac, colFrac[x])
        }
        let colThresh = max(0.10, maxColFrac * 0.35)
        var colRuns: [(Int, Int)] = []
        var start = -1
        for x in 0..<w {
            let ok = colFrac[x] > colThresh
            if ok && start < 0 { start = x }
            if !ok && start >= 0 { colRuns.append((start, x - 1)); start = -1 }
        }
        if start >= 0 { colRuns.append((start, w - 1)) }
        let centerX = w / 2
        let candidates = colRuns.filter { $0.1 - $0.0 + 1 > w / 2 }
        guard let colRun = candidates.min(by: {
            abs(($0.0 + $0.1) / 2 - centerX) < abs(($1.0 + $1.1) / 2 - centerX)
        }) else { return nil }
        var x0 = colRun.0, x1 = colRun.1

        // --- Row profile inside the detected columns. Exclude toolbar rows, which are
        // full-window-width and would otherwise merge with the display run.
        var rowFrac = [Double](repeating: 0, count: h)
        var maxRowFrac = 0.0
        let xStep = max(1, (x1 - x0) / 200)
        let xIndices = Array(stride(from: x0 + 8, to: max(x0 + 9, x1 - 8), by: xStep))
        for y in 0..<h {
            var nonBg = 0
            var fullRow = 0
            for x in 0..<w where !bmp.isBackground(x: x, y: y) { fullRow += 1 }
            for x in xIndices where !bmp.isBackground(x: x, y: y) { nonBg += 1 }
            rowFrac[y] = Double(nonBg) / Double(max(1, xIndices.count))
            if fullRow > Int(Double(w) * 0.985) && Double(y) < Double(h) * 0.15 {
                rowFrac[y] = 0 // toolbar row
            }
            maxRowFrac = max(maxRowFrac, rowFrac[y])
        }
        let rowThresh = max(0.10, maxRowFrac * 0.35)
        var rowRuns: [(Int, Int)] = []
        start = -1
        for y in 0..<h {
            let ok = rowFrac[y] > rowThresh
            if ok && start < 0 { start = y }
            if !ok && start >= 0 { rowRuns.append((start, y - 1)); start = -1 }
        }
        if start >= 0 { rowRuns.append((start, h - 1)) }
        guard let rowRun = rowRuns.filter({ $0.1 - $0.0 + 1 > h / 2 }).max(by: { ($0.1 - $0.0) < ($1.1 - $1.0) }) else {
            return nil
        }
        var y0 = rowRun.0, y1 = rowRun.1

        // Trim a couple of pixels of anti-aliasing.
        x0 += 1; x1 -= 1; y0 += 1; y1 -= 1
        guard x1 > x0, y1 > y0 else { return nil }
        let rect = CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)

        // --- Validate shape: portrait phone-like aspect.
        let aspect = rect.width / rect.height
        guard aspect > 0.42, aspect < 0.50 else { return nil }
        guard rect.width > Double(w) * 0.5, rect.height > Double(h) * 0.5 else { return nil }

        // --- Confidence from boundary contrast.
        var outsideBg = 0, insideContent = 0, checks = 0
        func check(_ x: Int, _ y: Int, expectBackground: Bool) {
            guard x >= 0, y >= 0, x < w, y < h else { return }
            let bg = bmp.isBackground(x: x, y: y)
            if expectBackground { outsideBg += bg ? 1 : 0 } else { insideContent += bg ? 0 : 1 }
            checks += 1
        }
        let mids = stride(from: 0.2, through: 0.8, by: 0.2).map { $0 }
        for t in mids {
            let yy = Int(rect.minY + rect.height * t)
            check(Int(rect.minX) - 4, yy, expectBackground: true)
            check(Int(rect.maxX) + 4, yy, expectBackground: true)
            check(Int(rect.minX) + 4, yy, expectBackground: false)
            check(Int(rect.maxX) - 4, yy, expectBackground: false)
            let xx = Int(rect.minX + rect.width * t)
            check(xx, Int(rect.minY) - 4, expectBackground: true)
            check(xx, Int(rect.maxY) + 4, expectBackground: true)
            check(xx, Int(rect.minY) + 4, expectBackground: false)
            check(xx, Int(rect.maxY) - 4, expectBackground: false)
        }
        let confidence = checks > 0 ? Double(outsideBg + insideContent) / Double(checks) : 0
        return DisplayDetection(rect: rect, confidence: confidence, method: "detected")
    }

    /// Best-effort display rect: live detection, then saved calibration, then a formula.
    public static func resolve(for frame: MirrorFrame) -> DisplayDetection {
        if let d = detect(in: frame.bitmap), d.confidence >= 0.6 {
            return d
        }
        if let c = loadCalibration() {
            let nr = c.normalizedRect
            let rect = CGRect(x: nr.minX * Double(frame.bitmap.width),
                              y: nr.minY * Double(frame.bitmap.height),
                              width: nr.width * Double(frame.bitmap.width),
                              height: nr.height * Double(frame.bitmap.height))
            return DisplayDetection(rect: rect, confidence: 0.5, method: "calibration")
        }
        // Formula: display is aspect-fit below the 38 pt title bar with ~8 pt side padding.
        let w = Double(frame.bitmap.width), h = Double(frame.bitmap.height)
        let aspect = 0.46025
        let sidePad = 16.0
        var dw = w - sidePad * 2
        var dh = dw / aspect
        let topPad = 76.0, bottomPad = 18.0
        if dh > h - topPad - bottomPad {
            dh = h - topPad - bottomPad
            dw = dh * aspect
        }
        let rect = CGRect(x: (w - dw) / 2, y: topPad, width: dw, height: dh)
        return DisplayDetection(rect: rect, confidence: 0.2, method: "formula")
    }

    /// Pixel point inside the display for normalized coordinates (0...1, top-left origin).
    public static func imagePoint(normX: Double, normY: Double, rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * normX, y: rect.minY + rect.height * normY)
    }

    /// Normalized coordinates for an image pixel inside the display.
    public static func normalized(point: CGPoint, rect: CGRect) -> (Double, Double) {
        ((point.x - rect.minX) / rect.width, (point.y - rect.minY) / rect.height)
    }
}
