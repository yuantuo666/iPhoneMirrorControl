import AppKit
import CoreGraphics
import Foundation

public struct HelperStatus {
    public let window: Bool
    public let authorized: Bool
    public let image: Bool
    public let windowId: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let pixelWidth: Double
    public let pixelHeight: Double
    public let ts: Double
    public let error: String?

    public init?(url: URL = Paths.statusFile) {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func num(_ k: String) -> Double { (obj[k] as? NSNumber)?.doubleValue ?? 0 }
        self.window = (obj["window"] as? Bool) ?? false
        self.authorized = (obj["authorized"] as? Bool) ?? false
        self.image = (obj["image"] as? Bool) ?? false
        self.windowId = Int(num("windowId"))
        self.x = num("x")
        self.y = num("y")
        self.width = num("width")
        self.height = num("height")
        self.pixelWidth = num("pixelWidth")
        self.pixelHeight = num("pixelHeight")
        self.ts = num("ts")
        self.error = obj["error"] as? String
    }
}

public struct MirrorFrame {
    public let status: HelperStatus
    public let bitmap: Bitmap
    public let fileDate: Date

    public var imageScaleX: Double { status.width > 0 ? status.pixelWidth / status.width : 2.0 }
    public var imageScaleY: Double { status.height > 0 ? status.pixelHeight / status.height : 2.0 }

    /// Convert a pixel point in the raw window capture into global screen points.
    public func screenPoint(fromImagePixel p: CGPoint) -> CGPoint {
        CGPoint(x: status.x + p.x / imageScaleX, y: status.y + p.y / imageScaleY)
    }
}

public enum FrameError: Error, CustomStringConvertible {
    case helperNotRunning
    case noStatus(String)
    case noImage(String)
    case displayNotDetected
    case helperUnauthorized

    public var description: String {
        switch self {
        case .helperNotRunning: return "Mirror capture helper is not running."
        case .noStatus(let s): return "Cannot read helper status: \(s)"
        case .noImage(let s): return "Cannot load captured image: \(s)"
        case .displayNotDetected: return "Could not locate the iPhone display inside the mirror window."
        case .helperUnauthorized: return "Screen recording permission is missing for the capture helper."
        }
    }
}

public enum Helper {
    public static func isRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "ClaudeMirrorHelper.app/Contents/MacOS/ClaudeMirrorHelper"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    @discardableResult
    public static func ensureRunning(launch: Bool = true) throws -> HelperStatus {
        Paths.ensureDirectories()
        if !isRunning() {
            guard launch else { throw FrameError.helperNotRunning }
            let app = Paths.defaultHelperApp
            guard FileManager.default.fileExists(atPath: app.path) else {
                throw FrameError.helperNotRunning
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = [app.path]
            try? p.run()
            p.waitUntilExit()
            // Give the helper time to start and write status.
            Thread.sleep(forTimeInterval: 1.5)
        }
        guard let st = HelperStatus() else {
            throw FrameError.noStatus(Paths.statusFile.path)
        }
        if !st.authorized {
            throw FrameError.helperUnauthorized
        }
        return st
    }

    public static func latestFrame() throws -> MirrorFrame {
        _ = try ensureRunning()
        // The helper writes the PNG and status.json separately; make sure we read a
        // status that belongs to the same capture (retry if it ticked in between).
        for _ in 0..<4 {
            guard let st1 = HelperStatus() else { throw FrameError.noStatus(Paths.statusFile.path) }
            if !st1.authorized { throw FrameError.helperUnauthorized }
            guard st1.image, st1.window else {
                throw FrameError.noStatus(st1.error ?? "helper reports no window/image")
            }
            guard let bmp = Bitmap(contentsOf: Paths.rawFrame) else {
                throw FrameError.noImage(Paths.rawFrame.path)
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: Paths.rawFrame.path)
            let date = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            if let st2 = HelperStatus(), st2.ts != st1.ts { continue }
            return MirrorFrame(status: st1, bitmap: bmp, fileDate: date)
        }
        guard let st = HelperStatus(), let bmp = Bitmap(contentsOf: Paths.rawFrame) else {
            throw FrameError.noImage(Paths.rawFrame.path)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: Paths.rawFrame.path)
        let date = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
        return MirrorFrame(status: st, bitmap: bmp, fileDate: date)
    }

    /// Wait until the helper writes a frame newer than `date`.
    public static func waitForFreshFrame(after date: Date, timeout: TimeInterval = 3.0) throws -> MirrorFrame {
        let deadline = Date().addingTimeInterval(timeout)
        var frame = try latestFrame()
        while frame.fileDate <= date && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.15)
            frame = try latestFrame()
        }
        return frame
    }

    public static func activateMirror() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenContinuity").first {
            app.activate(options: [])
            Thread.sleep(forTimeInterval: 0.25)
        }
    }
}
