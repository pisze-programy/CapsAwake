import Foundation
import os

/// Single logging entry point for the app process. Every log line goes to
/// `os_log` and to one bounded file: ~/Library/Logs/CapsAwake/capsawake.log.
/// The file is rotated to capsawake.log.old when it grows past 1 MB.
enum AppLog {
    private static let subsystem = "com.piszeprogramy.capsawake"
    private static let osLogger = Logger(subsystem: subsystem, category: "app")

    private static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/CapsAwake", isDirectory: true)

    static var logDirectoryURL: URL { directory }
    private static let fileURL = directory.appendingPathComponent("capsawake.log")
    private static let backupURL = directory.appendingPathComponent("capsawake.log.old")
    private static let rotationLimit: UInt64 = 1_000_000

    private static let queue = DispatchQueue(label: "\(subsystem).applog")
    private static let dateFormatter = ISO8601DateFormatter()

    static func info(_ message: String) { write(level: "INFO", message: message) }
    static func warning(_ message: String) { write(level: "WARN", message: message) }
    static func error(_ message: String) { write(level: "ERROR", message: message) }

    private static func write(level: String, message: String) {
        switch level {
        case "ERROR": osLogger.error("\(message, privacy: .public)")
        case "WARN": osLogger.warning("\(message, privacy: .public)")
        default: osLogger.info("\(message, privacy: .public)")
        }
        let timestamp = Date()
        queue.async {
            let line = "\(dateFormatter.string(from: timestamp)) \(level) \(message)\n"
            persist(line)
        }
    }

    private static func persist(_ line: String) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            if let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? UInt64,
               size > rotationLimit {
                try? FileManager.default.removeItem(at: backupURL)
                try FileManager.default.moveItem(at: fileURL, to: backupURL)
            }
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try line.data(using: .utf8)?.write(to: fileURL)
            } else {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            }
        } catch {
            osLogger.error("log write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
