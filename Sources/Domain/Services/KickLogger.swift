// Sources/Domain/Services/KickLogger.swift
// キック処理のログ出力

import Foundation

/// キック処理用のロガー
/// ログは ~/Library/Application Support/AIAgentPM/kick.log に出力
public enum KickLogger {
    private static let logFileName = "kick.log"

    private static var logPath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("AIAgentPM")

        // ディレクトリがなければ作成
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir.appendingPathComponent(logFileName).path
    }

    /// ログを出力
    public static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"

        // コンソール出力
        print(logLine, terminator: "")

        // ファイル出力
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: logLine.data(using: .utf8))
        }
    }

    /// ログをクリア
    public static func clear() {
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}
