import Cocoa
import CoreGraphics
import ScreenCaptureKit
import Foundation

// Capture the iPhone Mirroring window into a PNG plus a small JSON status file.
// Screen Recording permission is required; grant it once in System Settings.

let captureDir: String = {
    if let v = ProcessInfo.processInfo.environment["MIRROR_CAPTURE_DIR"], !v.isEmpty { return v }
    return NSString(string: "~/.local/share/iphone-mirror/capture").expandingTildeInPath
}()
let outDir = captureDir
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func log(_ s: String) {
    let line = "[\(Date())] \(s)\n"
    guard let d = line.data(using: .utf8) else { return }
    let p = "\(outDir)/helper.log"
    if let fh = FileHandle(forWritingAtPath: p) {
        fh.seekToEndOfFile(); fh.write(d); fh.closeFile()
    } else {
        try? d.write(to: URL(fileURLWithPath: p))
    }
}

func writeStatus(_ dict: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) {
        try? data.write(to: URL(fileURLWithPath: "\(outDir)/status.json"))
    }
}

let authorized = CGPreflightScreenCaptureAccess()
log("start screenCapturePreflight=\(authorized)")

func findMirrorWindow(in content: SCShareableContent) -> SCWindow? {
    for w in content.windows {
        if w.owningApplication?.bundleIdentifier == "com.apple.ScreenContinuity"
            && w.frame.width > 100 && w.frame.height > 100 {
            return w
        }
    }
    for w in content.windows {
        let name = (w.owningApplication?.applicationName ?? "").lowercased()
        if name.contains("mirror") && w.frame.width > 100 && w.frame.height > 100 {
            return w
        }
    }
    return nil
}

func captureLoop() async {
    let activity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiatedAllowingIdleSystemSleep], reason: "iPhone Mirroring capture")
    _ = activity
    while true {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = findMirrorWindow(in: content) else {
                writeStatus(["window": false, "authorized": CGPreflightScreenCaptureAccess(),
                             "ts": Date().timeIntervalSince1970])
                try? await Task.sleep(nanoseconds: 800_000_000)
                continue
            }
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let rep = NSBitmapImageRep(cgImage: img)
            if let data = rep.representation(using: .png, properties: [:]) {
                let tmp = "\(outDir)/live.tmp.png"
                let dst = "\(outDir)/live.png"
                try? data.write(to: URL(fileURLWithPath: tmp))
                try? FileManager.default.removeItem(atPath: dst)
                try? FileManager.default.moveItem(atPath: tmp, toPath: dst)
            }
            writeStatus([
                "window": true, "authorized": CGPreflightScreenCaptureAccess(), "image": true,
                "windowId": Int(window.windowID),
                "x": window.frame.origin.x, "y": window.frame.origin.y,
                "width": window.frame.width, "height": window.frame.height,
                "pixelWidth": img.width, "pixelHeight": img.height,
                "ts": Date().timeIntervalSince1970,
            ])
            try? await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            writeStatus(["window": false, "authorized": CGPreflightScreenCaptureAccess(),
                         "error": String(describing: error), "ts": Date().timeIntervalSince1970])
            log("capture error: \(error)")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
Task { await captureLoop() }
log("helper started")
app.run()
