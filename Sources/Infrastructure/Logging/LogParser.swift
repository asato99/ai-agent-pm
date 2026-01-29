// Sources/Infrastructure/Logging/LogParser.swift
// ログ行のパーサー

import Foundation

/// ログ行をパースしてLogEntryに変換
///
/// JSON形式とレガシーテキスト形式の両方をサポート。
public enum LogParser {

    // MARK: - Public API

    /// 単一のログ行をパース
    ///
    /// - Parameter line: ログ行（JSONまたはテキスト形式）
    /// - Returns: パースされたLogEntry、またはnil（空行の場合）
    public static func parse(_ line: String) -> LogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // JSON形式を試行
        if trimmed.hasPrefix("{") {
            if let entry = parseJson(trimmed) {
                return entry
            }
        }

        // テキスト形式としてパース
        return parseText(trimmed)
    }

    /// 複数のログ行をパース
    ///
    /// - Parameter lines: ログ行の配列
    /// - Returns: パースされたLogEntryの配列（パース失敗行は除外）
    public static func parseAll(_ lines: [String]) -> [LogEntry] {
        return lines.compactMap { parse($0) }
    }

    // MARK: - JSON Parsing

    private static func parseJson(_ json: String) -> LogEntry? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // 必須フィールドの確認
        guard let message = dict["message"] as? String else {
            return nil
        }

        // タイムスタンプのパース
        let timestamp: Date
        if let timestampStr = dict["timestamp"] as? String {
            timestamp = parseTimestamp(timestampStr) ?? Date()
        } else {
            timestamp = Date()
        }

        // ログレベルのパース
        let level: LogLevel
        if let levelStr = dict["level"] as? String,
           let parsedLevel = LogLevel(rawString: levelStr) {
            level = parsedLevel
        } else {
            level = .info
        }

        // カテゴリのパース
        let category: LogCategory
        if let categoryStr = dict["category"] as? String,
           let parsedCategory = LogCategory(rawValue: categoryStr) {
            category = parsedCategory
        } else {
            category = .system
        }

        // オプションフィールド
        let operation = dict["operation"] as? String
        let agentId = dict["agent_id"] as? String
        let projectId = dict["project_id"] as? String
        let details = dict["details"] as? [String: Any]

        return LogEntry(
            timestamp: timestamp,
            level: level,
            category: category,
            message: message,
            operation: operation,
            agentId: agentId,
            projectId: projectId,
            details: details
        )
    }

    // MARK: - Text Parsing

    private static func parseText(_ text: String) -> LogEntry? {
        // 新しいテキスト形式: 2026-01-29 13:26:16.836 [LEVEL] [category] [operation] message
        // レガシー形式: [timestamp] message
        var timestamp = Date()
        var level: LogLevel = .info
        var category: LogCategory = .system
        var operation: String?
        var message = text

        // パターン: 2026-01-29 13:26:16.836 [LEVEL] [category] [operation]? message
        // operation部分はオプショナル
        let pattern = #"^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3})\s+\[(\w+)\]\s+\[(\w+)\](?:\s+\[([^\]]+)\])?\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            // タイムスタンプ
            if let timestampRange = Range(match.range(at: 1), in: text) {
                let timestampStr = String(text[timestampRange])
                if let parsedTimestamp = parseTextTimestamp(timestampStr) {
                    timestamp = parsedTimestamp
                }
            }

            // レベル
            if let levelRange = Range(match.range(at: 2), in: text) {
                let levelStr = String(text[levelRange])
                if let parsedLevel = LogLevel(rawString: levelStr) {
                    level = parsedLevel
                }
            }

            // カテゴリ
            if let categoryRange = Range(match.range(at: 3), in: text) {
                let categoryStr = String(text[categoryRange])
                if let parsedCategory = LogCategory(rawValue: categoryStr) {
                    category = parsedCategory
                }
            }

            // オペレーション（オプショナル）
            if match.range(at: 4).location != NSNotFound,
               let operationRange = Range(match.range(at: 4), in: text) {
                operation = String(text[operationRange])
            }

            // メッセージ
            if let messageRange = Range(match.range(at: 5), in: text) {
                message = String(text[messageRange])
            }
        } else {
            // レガシー形式: [timestamp] [LEVEL] [category] message
            let legacyPattern = #"^\[([^\]]+)\]\s+\[(\w+)\]\s+\[(\w+)\]\s+(.+)$"#
            if let regex = try? NSRegularExpression(pattern: legacyPattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let levelRange = Range(match.range(at: 2), in: text) {
                    let levelStr = String(text[levelRange])
                    if let parsedLevel = LogLevel(rawString: levelStr) {
                        level = parsedLevel
                    }
                }
                if let categoryRange = Range(match.range(at: 3), in: text) {
                    let categoryStr = String(text[categoryRange])
                    if let parsedCategory = LogCategory(rawValue: categoryStr) {
                        category = parsedCategory
                    }
                }
                if let messageRange = Range(match.range(at: 4), in: text) {
                    message = String(text[messageRange])
                }
            } else {
                // 最もシンプルなレガシー形式: [timestamp] message
                let simpleLegacyPattern = #"^\[([^\]]+)\]\s+(.+)$"#
                if let regex = try? NSRegularExpression(pattern: simpleLegacyPattern),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let messageRange = Range(match.range(at: 2), in: text) {
                        message = String(text[messageRange])
                    }
                }
            }
        }

        return LogEntry(
            timestamp: timestamp,
            level: level,
            category: category,
            message: message,
            operation: operation
        )
    }

    /// テキスト形式のタイムスタンプをパース
    ///
    /// フォーマット: "yyyy-MM-dd HH:mm:ss.SSS"
    private static func parseTextTimestamp(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: str)
    }

    // MARK: - Helpers

    private static func parseTimestamp(_ str: String) -> Date? {
        // ISO8601形式のパース
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) {
            return date
        }

        // フラクショナル秒なしでも試行
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }
}
