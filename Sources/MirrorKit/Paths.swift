import Foundation

public enum Paths {
    public static var captureDir: URL {
        if let v = ProcessInfo.processInfo.environment["MIRROR_CAPTURE_DIR"] {
            return URL(fileURLWithPath: v)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/iphone-mirror/capture")
    }

    public static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/iPhoneMirror")
    }

    public static var calibrationFile: URL {
        supportDir.appendingPathComponent("calibration.json")
    }

    public static var rawFrame: URL { captureDir.appendingPathComponent("live.png") }
    public static var statusFile: URL { captureDir.appendingPathComponent("status.json") }

    public static var defaultHelperApp: URL {
        if let v = ProcessInfo.processInfo.environment["MIRROR_HELPER_APP"] {
            return URL(fileURLWithPath: v)
        }
        // Prefer the installed helper (stable location), then the repo build.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let installed = home.appendingPathComponent(
            "Library/Application Support/iPhoneMirror/Helper/ClaudeMirrorHelper.app")
        if FileManager.default.fileExists(atPath: installed.path) { return installed }
        let repo = home.appendingPathComponent(
            "code/swift/iPhoneMirror/Helper/ClaudeMirrorHelper.app")
        if FileManager.default.fileExists(atPath: repo.path) { return repo }
        return URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("ClaudeMirrorHelper.app")
    }

    public static func ensureDirectories() {
        try? FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }
}
