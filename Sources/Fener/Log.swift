import Foundation

/// A small append-only log at ~/Library/Logs/fener/fener.log (Console.app lists it under
/// Log Reports). Rotated to fener.log.1 past 1 MB. Logs events and failures, never
/// clipboard contents or what is typed.
enum Log {
    static let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/fener")
    static let file = dir.appendingPathComponent("fener.log")
    static let maxBytes = 1_000_000
    /// Off under XCTest, so test runs never write to the user's real log.
    static let enabled = NSClassFromString("XCTestCase") == nil
    private static let queue = DispatchQueue(label: "fener.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()

    static func info(_ message: String) { write("info", message) }
    static func error(_ message: String) { write("error", message) }

    private static func write(_ level: String, _ message: String) {
        guard enabled else { return }
        let line = "\(stamp.string(from: Date())) \(level) \(message.replacingOccurrences(of: "\n", with: "\n    "))\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > maxBytes {
                let old = dir.appendingPathComponent("fener.log.1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: file, to: old)
            }
            if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            guard let h = try? FileHandle(forWritingTo: file) else { return }
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        }
    }

    /// A handle that appends to the log, for child processes' stderr.
    static func handle() -> FileHandle {
        guard enabled else { return FileHandle.nullDevice }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let h = try? FileHandle(forWritingTo: file) else { return FileHandle.nullDevice }
        h.seekToEndOfFile()
        return h
    }

    /// `fener log [-f]`: the last lines, or follow with tail -f.
    static func show(follow: Bool) -> Int32 {
        guard FileManager.default.fileExists(atPath: file.path) else { print("no log yet (\(file.path))"); return 0 }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        p.arguments = (follow ? ["-n", "40", "-f"] : ["-n", "40"]) + [file.path]
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
