import Foundation

/// The most recent synthetic tap, persisted so annotated screenshots can show
/// where the previous click landed (useful for calibrating by eye).
public struct LastTap: Codable {
    public var normX: Double
    public var normY: Double
    public var screenX: Double
    public var screenY: Double
    public var ts: Double
    public var windowWidth: Double
    public var windowHeight: Double
    public var displayWidth: Double
    public var displayHeight: Double

    public init(normX: Double, normY: Double, screenX: Double, screenY: Double,
                ts: Double = Date().timeIntervalSince1970,
                windowWidth: Double, windowHeight: Double,
                displayWidth: Double, displayHeight: Double) {
        self.normX = normX
        self.normY = normY
        self.screenX = screenX
        self.screenY = screenY
        self.ts = ts
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
    }

    public static var fileURL: URL {
        Paths.supportDir.appendingPathComponent("last-tap.json")
    }

    public static func save(_ tap: LastTap) {
        Paths.ensureDirectories()
        if let data = try? JSONEncoder().encode(tap) {
            try? data.write(to: fileURL)
        }
    }

    public static func load(maxAge: TimeInterval = 600) -> LastTap? {
        guard let data = try? Data(contentsOf: fileURL),
              let tap = try? JSONDecoder().decode(LastTap.self, from: data) else { return nil }
        guard Date().timeIntervalSince1970 - tap.ts <= maxAge else { return nil }
        return tap
    }
}
