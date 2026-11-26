import AppKit
import CoreGraphics
import Foundation
import MirrorKit

// MARK: - small argument parser

struct Args {
    var positional: [String] = []
    var flags: Set<String> = []
    var values: [String: String] = [:]

    init(_ raw: [String], valueFlags: Set<String>) {
        var i = 0
        while i < raw.count {
            let a = raw[i]
            if a.hasPrefix("--") {
                let name = String(a.dropFirst(2))
                if valueFlags.contains(name), i + 1 < raw.count {
                    values[name] = raw[i + 1]
                    i += 2
                    continue
                }
                flags.insert(name)
                i += 1
            } else {
                positional.append(a)
                i += 1
            }
        }
    }

    func value(_ name: String) -> String? { values[name] }
    func has(_ name: String) -> Bool { flags.contains(name) }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func jsonPrint(_ obj: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let s = String(data: data, encoding: .utf8) {
        print(s)
    }
}

func savePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "mirrorctl", code: 1, userInfo: [NSLocalizedDescriptionKey: "png encode failed"])
    }
    try data.write(to: url)
}

// MARK: - shared helpers

func loadFrame() -> MirrorFrame {
    do { return try Helper.latestFrame() }
    catch { fail("\(error)") }
}

struct Aim {
    let screen: CGPoint
    let imagePoint: CGPoint   // inside the raw window capture
    let normX: Double
    let normY: Double
    let rect: CGRect
}

func resolveAim(_ x: Double, _ y: Double, space: String,
                frame: MirrorFrame, detection: DisplayDetection) -> Aim {
    let rect = detection.rect
    var screen = CGPoint.zero
    var imagePoint = CGPoint.zero
    switch space {
    case "norm":
        let nx = x / 100.0, ny = y / 100.0
        guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else {
            fail("norm coordinates must be percentages 0...100")
        }
        imagePoint = Display.imagePoint(normX: nx, normY: ny, rect: rect)
        screen = frame.screenPoint(fromImagePixel: imagePoint)
    case "px":
        imagePoint = CGPoint(x: rect.minX + x, y: rect.minY + y)
        guard x >= 0, x <= rect.width, y >= 0, y <= rect.height else {
            fail("px coordinates must be inside the display crop (0...\(Int(rect.width)) x 0...\(Int(rect.height)))")
        }
        screen = frame.screenPoint(fromImagePixel: imagePoint)
    case "screen":
        screen = CGPoint(x: x, y: y)
        imagePoint = CGPoint(x: (x - frame.status.x) * frame.imageScaleX,
                             y: (y - frame.status.y) * frame.imageScaleY)
    default:
        fail("unknown --space \(space) (use norm|px|screen)")
    }
    let (nx, ny) = Display.normalized(point: imagePoint, rect: rect)
    return Aim(screen: screen, imagePoint: imagePoint, normX: nx, normY: ny, rect: rect)
}

func renderAim(_ frame: MirrorFrame, _ detection: DisplayDetection, aim: Aim, out: URL,
               ocrHits: [OCRHit] = [], drawOCR: Bool = false) {
    var opts = AnnotateOptions()
    opts.crosshair = (aim.normX, aim.normY)
    opts.ocrHits = ocrHits
    opts.drawOCRHits = drawOCR
    opts.footer = String(format: "target %.1f%%, %.1f%%  screen (%.1f, %.1f)  display %@",
                         aim.normX * 100, aim.normY * 100, aim.screen.x, aim.screen.y,
                         "\(Int(detection.rect.width))x\(Int(detection.rect.height))")
    guard let img = Annotate.render(frame: frame, detection: detection, options: opts) else {
        fail("render failed")
    }
    do { try savePNG(img, to: out) } catch { fail("\(error)") }
}

func detectionJSON(_ frame: MirrorFrame, _ d: DisplayDetection) -> [String: Any] {
    [
        "window": [
            "id": frame.status.windowId,
            "x": frame.status.x, "y": frame.status.y,
            "width": frame.status.width, "height": frame.status.height,
        ],
        "image": ["width": frame.bitmap.width, "height": frame.bitmap.height,
                  "scaleX": frame.imageScaleX, "scaleY": frame.imageScaleY],
        "display": [
            "x": d.rect.minX, "y": d.rect.minY,
            "width": d.rect.width, "height": d.rect.height,
            "aspect": d.rect.width / d.rect.height,
            "method": d.method, "confidence": d.confidence,
        ],
    ]
}

// MARK: - commands

func cmdStatus(_ args: Args) {
    let frame = loadFrame()
    let d = Display.resolve(for: frame)
    if args.has("json") {
        jsonPrint(detectionJSON(frame, d))
        return
    }
    print("window id \(frame.status.windowId) at (\(frame.status.x), \(frame.status.y)) \(Int(frame.status.width))x\(Int(frame.status.height)) pt")
    print("capture \(frame.bitmap.width)x\(frame.bitmap.height) px  scale \(frame.imageScaleX)x")
    print(String(format: "display rect (%.0f, %.0f) %.0fx%.0f px  aspect %.3f  %@ confidence %.2f",
                 d.rect.minX, d.rect.minY, d.rect.width, d.rect.height,
                 d.rect.width / d.rect.height, d.method, d.confidence))
    print("helper frame age \(String(format: "%.2f", Date().timeIntervalSince(frame.fileDate)))s")
}

func cmdCapture(_ args: Args) {
    let frame = loadFrame()
    let d = Display.resolve(for: frame)
    var opts = AnnotateOptions()
    opts.drawGrid = !args.has("no-grid")
    if let f = args.value("footer") { opts.footer = f }
    if args.has("ocr") || args.has("ocr-boxes") {
        let crop = frame.bitmap.cropped(to: d.rect)
        if let cg = crop.cgImage(), let recognized = try? OCR.recognize(cgImage: cg) {
            opts.ocrHits = recognized
            opts.drawOCRHits = args.has("ocr-boxes")
        }
    }
    guard let img = Annotate.render(frame: frame, detection: d, options: opts) else { fail("render failed") }
    let out = URL(fileURLWithPath: args.value("out") ?? Paths.captureDir.appendingPathComponent("annotated.png").path)
    do { try savePNG(img, to: out) } catch { fail("\(error)") }
    if args.has("json") {
        var obj = detectionJSON(frame, d)
        obj["imagePath"] = out.path
        jsonPrint(obj)
    } else {
        print(out.path)
    }
}

func cmdClick(_ args: Args) {
    guard args.positional.count >= 2, let x = Double(args.positional[0]), let y = Double(args.positional[1]) else {
        fail("usage: mirrorctl click <x> <y> [--space norm|px|screen]")
    }
    let space = args.value("space") ?? "norm"
    let frame = loadFrame()
    let d = Display.resolve(for: frame)
    let aim = resolveAim(x, y, space: space, frame: frame, detection: d)

    if args.has("dry-run") {
        let out = URL(fileURLWithPath: args.value("out") ?? Paths.captureDir.appendingPathComponent("aim.png").path)
        renderAim(frame, d, aim: aim, out: out)
        print(String(format: "aim %.2f%%, %.2f%% -> image (%.1f, %.1f) -> screen (%.1f, %.1f)",
                     aim.normX * 100, aim.normY * 100, aim.imagePoint.x, aim.imagePoint.y, aim.screen.x, aim.screen.y))
        print(out.path)
        return
    }

    Helper.activateMirror()
    let before = frame.bitmap
    let beforeDate = frame.fileDate
    Input.click(at: aim.screen, doubleClick: args.has("double"), holdMs: Int(args.value("hold") ?? "90") ?? 90)
    print(String(format: "clicked %.2f%%, %.2f%% at screen (%.1f, %.1f)", aim.normX * 100, aim.normY * 100, aim.screen.x, aim.screen.y))

    if args.has("verify") {
        Thread.sleep(forTimeInterval: 1.0)
        if let after = try? Helper.waitForFreshFrame(after: beforeDate, timeout: 3.0) {
            let d2 = Display.resolve(for: after)
            let ratio = Diff.ratio(before, after.bitmap, region: bestRegion(d2.rect, before, after.bitmap))
            print(String(format: "screen diff %.2f%%%@", ratio * 100,
                         ratio < 0.003 ? "  (looks unchanged — tap may have missed)" : ""))
        } else {
            print("could not capture a fresh frame to verify")
        }
    }
}

func bestRegion(_ a: CGRect, _ imgA: Bitmap, _ imgB: Bitmap) -> CGRect {
    // Use the smaller image rect so both sides sample valid pixels.
    let w = min(imgA.width, imgB.width), h = min(imgA.height, imgB.height)
    let r = a.intersection(CGRect(x: 0, y: 0, width: w, height: h))
    return r.isNull ? CGRect(x: 0, y: 0, width: w, height: h) : r
}

func cmdDrag(_ args: Args) {
    guard args.positional.count >= 4,
          let x1 = Double(args.positional[0]), let y1 = Double(args.positional[1]),
          let x2 = Double(args.positional[2]), let y2 = Double(args.positional[3]) else {
        fail("usage: mirrorctl drag <x1> <y1> <x2> <y2> [--space norm|px|screen] [--duration ms]")
    }
    let space = args.value("space") ?? "norm"
    let frame = loadFrame()
    let d = Display.resolve(for: frame)
    let a = resolveAim(x1, y1, space: space, frame: frame, detection: d)
    let b = resolveAim(x2, y2, space: space, frame: frame, detection: d)
    Helper.activateMirror()
    let dur = Int(args.value("duration") ?? "280") ?? 280
    Input.drag(from: a.screen, to: b.screen, durationMs: dur)
    print(String(format: "dragged (%.1f, %.1f) -> (%.1f, %.1f) in %dms", a.screen.x, a.screen.y, b.screen.x, b.screen.y, dur))
}

func cmdMove(_ args: Args) {
    guard args.positional.count >= 2, let x = Double(args.positional[0]), let y = Double(args.positional[1]) else {
        fail("usage: mirrorctl move <x> <y> [--space norm|px|screen]")
    }
    let space = args.value("space") ?? "norm"
    let frame = loadFrame()
    let d = Display.resolve(for: frame)
    let aim = resolveAim(x, y, space: space, frame: frame, detection: d)
    Input.warp(to: aim.screen)
    print(String(format: "cursor at screen (%.1f, %.1f)", aim.screen.x, aim.screen.y))
}

func cmdKey(_ args: Args) {
    guard let first = args.positional.first, let code = UInt16(first) else {
        fail("usage: mirrorctl key <keycode> [cmd] [shift] [opt] [ctrl]")
    }
    var flags: CGEventFlags = []
    for f in args.positional.dropFirst() {
        switch f {
        case "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt": flags.insert(.maskAlternate)
        case "ctrl": flags.insert(.maskControl)
        default: break
        }
    }
    Helper.activateMirror()
    Input.key(code: code, flags: flags)
    print("key \(code) sent")
}

func cmdText(_ args: Args) {
    guard !args.positional.isEmpty else { fail("usage: mirrorctl text <string>") }
    let text = args.positional.joined(separator: " ")
    Helper.activateMirror()
    Input.type(text: text)
    print("typed \(text.count) chars")
}

func ocrHitsForFrame(_ frame: MirrorFrame, _ d: DisplayDetection, args: Args) -> [OCRHit] {
    let crop = frame.bitmap.cropped(to: d.rect)
    guard let cg = crop.cgImage() else { return [] }
    let langs = (args.value("lang") ?? "zh-Hans,en-US").split(separator: ",").map(String.init)
    return (try? OCR.recognize(cgImage: cg, languages: langs)) ?? []
}

func cmdOCR(_ args: Args) {
    let frame = loadFrame()
    let d = Display.resolve(for: frame)
    let hits = ocrHitsForFrame(frame, d, args: args)
    if args.has("json") {
        jsonPrint(["hits": hits.map {
            ["text": $0.text, "confidence": $0.confidence,
             "x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h,
             "centerX": $0.centerX, "centerY": $0.centerY]
        }])
    } else {
        for h in hits where h.confidence > 0.3 {
            print(String(format: "%5.1f%% %5.1f%%  %@", h.centerX * 100, h.centerY * 100, h.text))
        }
    }
}

func cmdFind(_ args: Args) {
    guard let needle = args.positional.first else { fail("usage: mirrorctl find <text> [--json]") }
    let frame = loadFrame()
    let d = Display.resolve(for: frame)
    let hits = ocrHitsForFrame(frame, d, args: args)
    let matches = hits.filter {
        args.has("exact") ? $0.text == needle : $0.text.localizedCaseInsensitiveContains(needle)
    }
    if args.has("json") {
        jsonPrint(["matches": matches.map {
            ["text": $0.text, "confidence": $0.confidence,
             "centerX": $0.centerX, "centerY": $0.centerY,
             "x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h]
        }])
        return
    }
    if matches.isEmpty { print("no match for \(needle)"); return }
    for (i, m) in matches.enumerated() {
        print(String(format: "[%d] %.1f%%, %.1f%%  conf %.2f  %@",
                     i, m.centerX * 100, m.centerY * 100, m.confidence, m.text))
    }
}

func cmdClickText(_ args: Args) {
    guard let needle = args.positional.first else { fail("usage: mirrorctl click-text <text> [--index n]") }
    let index = Int(args.value("index") ?? "0") ?? 0
    let frame = loadFrame()
    let d = Display.resolve(for: frame)
    let hits = ocrHitsForFrame(frame, d, args: args)
    let matches = hits.filter { $0.text.localizedCaseInsensitiveContains(needle) }
    guard matches.count > index else { fail("no OCR match for \(needle) (index \(index))") }
    let m = matches[index]
    let aim = resolveAim(m.centerX * 100, m.centerY * 100, space: "norm", frame: frame, detection: d)
    if args.has("dry-run") {
        let out = URL(fileURLWithPath: args.value("out") ?? Paths.captureDir.appendingPathComponent("aim.png").path)
        renderAim(frame, d, aim: aim, out: out, ocrHits: matches, drawOCR: true)
        print(String(format: "match \"%@\" at %.1f%%, %.1f%% -> screen (%.1f, %.1f)",
                     m.text, m.centerX * 100, m.centerY * 100, aim.screen.x, aim.screen.y))
        print(out.path)
        return
    }
    Helper.activateMirror()
    let beforeDate = frame.fileDate
    Input.click(at: aim.screen, doubleClick: args.has("double"))
    print(String(format: "clicked \"%@\" at %.1f%%, %.1f%%", m.text, m.centerX * 100, m.centerY * 100))
    if args.has("verify") {
        Thread.sleep(forTimeInterval: 1.0)
        if let after = try? Helper.waitForFreshFrame(after: beforeDate, timeout: 3.0) {
            let d2 = Display.resolve(for: after)
            let ratio = Diff.ratio(frame.bitmap, after.bitmap, region: bestRegion(d2.rect, frame.bitmap, after.bitmap))
            print(String(format: "screen diff %.2f%%%@", ratio * 100,
                         ratio < 0.003 ? "  (looks unchanged — tap may have missed)" : ""))
        }
    }
}

func cmdCalibrate(_ args: Args) {
    let frame = loadFrame()
    let detected = Display.detect(in: frame.bitmap)
    let resolved = Display.resolve(for: frame)
    if let d = detected {
        print(String(format: "detected display (%.0f, %.0f) %.0fx%.0f px, aspect %.3f, confidence %.2f",
                     d.rect.minX, d.rect.minY, d.rect.width, d.rect.height,
                     d.rect.width / d.rect.height, d.confidence))
    } else {
        print("display detection failed; falling back to \(resolved.method)")
    }
    print(String(format: "using display (%.0f, %.0f) %.0fx%.0f px [%@]",
                 resolved.rect.minX, resolved.rect.minY, resolved.rect.width,
                 resolved.rect.height, resolved.method))
    if args.has("save"), let d = detected, d.confidence >= 0.6 {
        let c = Calibration(windowWidth: frame.status.width, windowHeight: frame.status.height,
                            imageWidth: frame.bitmap.width, imageHeight: frame.bitmap.height,
                            displayX: d.rect.minX, displayY: d.rect.minY,
                            displayW: d.rect.width, displayH: d.rect.height,
                            aspect: d.rect.width / d.rect.height,
                            savedAt: ISO8601DateFormatter().string(from: Date()))
        Display.saveCalibration(c)
        print("saved calibration to \(Paths.calibrationFile.path)")
    }
    if args.has("json") {
        jsonPrint(detectionJSON(frame, resolved))
    }
    if args.has("aim") {
        // Render 9-point probe image so the mapping can be checked by eye.
        var opts = AnnotateOptions()
        opts.crosshair = (0.5, 0.5)
        opts.footer = "calibration probe: center crosshair 50%, 50%"
        if let img = Annotate.render(frame: frame, detection: resolved, options: opts) {
            let out = Paths.captureDir.appendingPathComponent("probe.png")
            try? savePNG(img, to: out)
            print(out.path)
        }
    }
}

func cmdHelper(_ args: Args) {
    if args.positional.first == "launch" {
        do {
            let st = try Helper.ensureRunning()
            print("helper running, authorized=\(st.authorized), windowId=\(st.windowId)")
        } catch { fail("\(error)") }
    } else {
        print("running=\(Helper.isRunning())")
        if let st = HelperStatus() {
            print("authorized=\(st.authorized) window=\(st.window) image=\(st.image) id=\(st.windowId)")
            if let e = st.error { print("error=\(e)") }
        }
        print("captureDir=\(Paths.captureDir.path)")
        print("helperApp=\(Paths.defaultHelperApp.path)")
    }
}

// MARK: - entry

let usage = """
mirrorctl — drive the mirrored iPhone by calibrated coordinates

Commands:
  status [--json]                                   show window / display geometry
  capture [--no-grid] [--ocr] [--ocr-boxes] [--out f] [--json]
                                                    annotated screenshot with % rulers
  click <x> <y> [--space norm|px|screen] [--dry-run] [--verify] [--double]
                                                    tap; norm space is 0..100 percent
  click-text <text> [--index n] [--dry-run] [--verify]
                                                    OCR + tap the matching text
  drag <x1> <y1> <x2> <y2> [--duration ms] [--space ...]
  move <x> <y> [--space ...]                        hover the Mac cursor
  key <keycode> [cmd] [shift] [opt] [ctrl]
  text <string>
  ocr [--json] [--lang zh-Hans,en-US]               recognized text with % coordinates
  find <text> [--exact] [--json]
  calibrate [--save] [--aim] [--json]               detect display rect, optionally save
  helper [launch|status]

Coordinates: --space norm is percent of the iPhone display (0,0 = top-left).
"""

let raw = Array(CommandLine.arguments.dropFirst())
guard let command = raw.first else {
    print(usage); exit(0)
}
let rest = Array(raw.dropFirst())
let args = Args(rest, valueFlags: ["space", "out", "duration", "index", "lang", "footer", "hold"])

switch command {
case "status": cmdStatus(args)
case "capture", "shot": cmdCapture(args)
case "click", "tap": cmdClick(args)
case "click-text": cmdClickText(args)
case "drag": cmdDrag(args)
case "move": cmdMove(args)
case "key": cmdKey(args)
case "text": cmdText(args)
case "ocr": cmdOCR(args)
case "find": cmdFind(args)
case "calibrate": cmdCalibrate(args)
case "helper": cmdHelper(args)
case "-h", "--help", "help": print(usage)
default:
    print("unknown command \(command)\n")
    print(usage)
    exit(2)
}
