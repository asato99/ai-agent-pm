// Sources/Infrastructure/Logging/LogLevel.swift
// ログレベル定義

import Foundation

/// ログの重要度レベル
///
/// TRACEが最も詳細で、ERRORが最も重要。
/// ログ出力時に最小レベルを設定することで、
/// それ以下の重要度のログをフィルタできる。
public enum LogLevel: Int, Comparable, Codable, Sendable, CaseIterable {
    /// 最も詳細なトレースログ（healthCheck等）
    case trace = 0

    /// デバッグ情報
    case debug = 1

    /// 通常の情報ログ（デフォルト）
    case info = 2

    /// 警告
    case warn = 3

    /// エラー
    case error = 4

    // MARK: - Comparable

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: - String Conversion

    /// 文字列からLogLevelを生成（大文字小文字を区別しない）
    ///
    /// - Parameter rawString: ログレベル文字列（"trace", "DEBUG"等）
    /// - Returns: 対応するLogLevel、無効な文字列の場合はnil
    public init?(rawString: String) {
        switch rawString.lowercased() {
        case "trace":
            self = .trace
        case "debug":
            self = .debug
        case "info":
            self = .info
        case "warn":
            self = .warn
        case "error":
            self = .error
        default:
            return nil
        }
    }

    /// 表示用の大文字文字列
    public var displayString: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }
}
