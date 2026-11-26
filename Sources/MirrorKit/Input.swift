import AppKit
import CoreGraphics
import Foundation

public enum Input {
    public static func warp(to p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(15_000)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: p.x + 0.5, y: p.y), mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    public static func click(at p: CGPoint, doubleClick: Bool = false, holdMs: Int = 90) {
        let src = CGEventSource(stateID: .hidSystemState)
        warp(to: p)
        usleep(60_000)
        func clickOnce() {
            CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            usleep(useconds_t(holdMs * 1000))
            CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        clickOnce()
        if doubleClick {
            usleep(80_000)
            clickOnce()
        }
    }

    public static func drag(from a: CGPoint, to b: CGPoint, durationMs: Int = 280) {
        let src = CGEventSource(stateID: .hidSystemState)
        let steps = max(10, durationMs / 16)
        let stepDelay = useconds_t(max(1, durationMs * 1000 / steps))
        warp(to: a)
        usleep(70_000)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: a, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(25_000)
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            usleep(stepDelay)
        }
        usleep(20_000)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: b, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    public static func type(text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        let chars = Array(text.utf16)
        guard !chars.isEmpty else { return }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            down.post(tap: .cghidEventTap)
        }
        usleep(40_000)
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            up.post(tap: .cghidEventTap)
        }
    }

    public static func key(code: UInt16, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        usleep(60_000)
        if let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }
}

public enum Diff {
    /// Fraction of sampled pixels that changed noticeably between two captures.
    public static func ratio(_ a: Bitmap, _ b: Bitmap, region: CGRect? = nil) -> Double {
        let maxX = Double(min(a.width, b.width))
        let maxY = Double(min(a.height, b.height))
        let regionMaxX = region.map { Double($0.maxX) } ?? maxX
        let regionMaxY = region.map { Double($0.maxY) } ?? maxY
        let x0 = max(0, Int(region?.minX ?? 0))
        let y0 = max(0, Int(region?.minY ?? 0))
        let x1 = min(Int(maxX), Int(regionMaxX))
        let y1 = min(Int(maxY), Int(regionMaxY))
        guard x1 > x0, y1 > y0 else { return 0 }
        var changed = 0, total = 0
        let step = max(1, min(x1 - x0, y1 - y0) / 220)
        for y in stride(from: y0, to: y1, by: step) {
            for x in stride(from: x0, to: x1, by: step) {
                let pa = a.pixel(x: x, y: y)
                let pb = b.pixel(x: x, y: y)
                let dr = abs(Int(pa.r) - Int(pb.r))
                let dg = abs(Int(pa.g) - Int(pb.g))
                let db = abs(Int(pa.b) - Int(pb.b))
                if dr + dg + db > 45 { changed += 1 }
                total += 1
            }
        }
        return total > 0 ? Double(changed) / Double(total) : 0
    }
}
