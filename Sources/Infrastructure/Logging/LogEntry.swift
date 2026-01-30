// Sources/Infrastructure/Logging/LogEntry.swift
// ログエントリ定義

import Foundation

/// 構造化ログの1エントリ
///
/// JSON形式とテキスト形式の両方で出力可能。
/// MCP Log Systemの中核データ構造。
public struct LogEntry: Codable, Sendable {
    /// タイムスタンプ
    public let timestamp: Date

    /// ログレベル
    public let level: LogLevel

    /// ログカテゴリ
    public let category: LogCategory

    /// ログメッセージ
    public let message: String

    /// 操作名（オプション）
    public let operation: String?

    /// エージェントID（オプション）
    public let agentId: String?

    /// プロジェクトID（オプション）
    public let projectId: String?

    /// 追加詳細情報（オプション）
    /// JSONシリアライズ可能な任意のデータ
    public let details: [String: Any]?

    // MARK: - Initialization

    public init(
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil,
        details: [String: Any]? = nil
    ) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.operation = operation
        self.agentId = agentId
        self.projectId = projectId
        self.details = details
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case level
        case category
        case message
        case operation
        case agentId = "agent_id"
        case projectId = "project_id"
        case details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        level = try container.decode(LogLevel.self, forKey: .level)
        category = try container.decode(LogCategory.self, forKey: .category)
        message = try container.decode(String.self, forKey: .message)
        operation = try container.decodeIfPresent(String.self, forKey: .operation)
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)

        // details は [String: Any] なので特別な処理が必要
        if let detailsData = try container.decodeIfPresent(Data.self, forKey: .details) {
            details = try JSONSerialization.jsonObject(with: detailsData) as? [String: Any]
        } else {
            details = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level, forKey: .level)
        try container.encode(category, forKey: .category)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(operation, forKey: .operation)
        try container.encodeIfPresent(agentId, forKey: .agentId)
        try container.encodeIfPresent(projectId, forKey: .projectId)

        // details は [String: Any] なので Data に変換してエンコード
        if let details = details {
            let detailsData = try JSONSerialization.data(withJSONObject: details)
            try container.encode(detailsData, forKey: .details)
        }
    }

    // MARK: - Output Formats

    /// JSON形式の文字列を生成
    ///
    /// 構造化ログ出力用。フィルタリングや検索に適した形式。
    public func toJSON() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var dict: [String: Any] = [
            "timestamp": dateFormatter.string(from: timestamp),
            "level": level.displayString,
            "category": category.rawValue,
            "message": message
        ]

        if let operation = operation {
            dict["operation"] = operation
        }
        if let agentId = agentId {
            dict["agent_id"] = agentId
        }
        if let projectId = projectId {
            dict["project_id"] = projectId
        }
        if let details = details {
            dict["details"] = details
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\":\"Failed to serialize log entry\"}"
        }
    }

    /// テキスト形式の文字列を生成
    ///
    /// 人間が読みやすい従来形式。デバッグやコンソール出力用。
    public func toText() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.timeZone = TimeZone.current

        var parts: [String] = [
            dateFormatter.string(from: timestamp),
            "[\(level.displayString)]",
            "[\(category.rawValue)]"
        ]

        if let operation = operation {
            parts.append("[\(operation)]")
        }

        if let agentId = agentId {
            parts.append("agent:\(agentId)")
        }

        if let projectId = projectId {
            parts.append("project:\(projectId)")
        }

        parts.append(message)

        // details がある場合は出力に追加
        if let details = details, !details.isEmpty {
            if let jsonData = try? JSONSerialization.data(withJSONObject: details, options: [.sortedKeys]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                parts.append("details:\(jsonString)")
            }
        }

        return parts.joined(separator: " ")
    }
}
