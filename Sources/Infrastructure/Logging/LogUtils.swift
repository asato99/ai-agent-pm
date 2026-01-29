// Sources/Infrastructure/Logging/LogUtils.swift
// ログ出力用ユーティリティ

import Foundation

/// ログ出力用のユーティリティ関数群
public enum LogUtils {

    /// デフォルトの最大長（2KB）
    public static let defaultMaxLength = 2000

    /// 切り詰めマーカー
    public static let truncationMarker = "...[truncated]"

    // MARK: - String Truncation

    /// 文字列を指定された最大長に切り詰める
    ///
    /// - Parameters:
    ///   - string: 切り詰める文字列
    ///   - maxLength: 最大長（デフォルト: 2000）
    /// - Returns: 切り詰められた文字列（マーカー付き）
    public static func truncate(_ string: String, maxLength: Int = defaultMaxLength) -> String {
        guard string.count > maxLength else {
            return string
        }

        let truncatedLength = maxLength - truncationMarker.count
        let index = string.index(string.startIndex, offsetBy: max(0, truncatedLength))
        return String(string[..<index]) + truncationMarker
    }

    // MARK: - Dictionary Truncation

    /// 辞書をJSON文字列に変換し、必要に応じて切り詰める
    ///
    /// - Parameters:
    ///   - dictionary: 切り詰める辞書
    ///   - maxLength: 最大長（デフォルト: 2000）
    /// - Returns: 切り詰められたJSON文字列
    public static func truncate(_ dictionary: [String: Any], maxLength: Int = defaultMaxLength) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
            guard let jsonString = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return truncate(jsonString, maxLength: maxLength)
        } catch {
            return "{\"error\": \"Failed to serialize\"}"
        }
    }

    // MARK: - Any Value Truncation

    /// 任意の値を切り詰める
    ///
    /// - Parameters:
    ///   - value: 切り詰める値
    ///   - maxLength: 最大長（デフォルト: 2000）
    /// - Returns: 切り詰められた値（文字列の場合は切り詰め、それ以外はそのまま）
    public static func truncateAny(_ value: Any, maxLength: Int = defaultMaxLength) -> Any {
        switch value {
        case let string as String:
            return truncate(string, maxLength: maxLength)

        case let dict as [String: Any]:
            // 辞書内の各値を再帰的に切り詰め
            var truncatedDict: [String: Any] = [:]
            for (key, val) in dict {
                truncatedDict[key] = truncateAny(val, maxLength: maxLength)
            }
            return truncatedDict

        case let array as [Any]:
            // 配列内の各要素を再帰的に切り詰め
            return array.map { truncateAny($0, maxLength: maxLength) }

        default:
            // その他の型はそのまま返す
            return value
        }
    }

    // MARK: - Arguments Formatting

    /// ツール引数を安全にログ用に整形する
    ///
    /// セッショントークンなどの機密情報をマスクし、
    /// 長い値を切り詰める。
    ///
    /// - Parameters:
    ///   - arguments: ツール引数
    ///   - maxLength: 最大長（デフォルト: 2000）
    /// - Returns: ログ用に整形された辞書
    public static func formatArguments(
        _ arguments: [String: Any],
        maxLength: Int = defaultMaxLength
    ) -> [String: Any] {
        var formatted: [String: Any] = [:]

        for (key, value) in arguments {
            // 機密情報をマスク（パスワード・シークレットのみ）
            // セッショントークンはデバッグ用途でマスクしない
            if key.lowercased().contains("passkey") ||
               key.lowercased().contains("password") ||
               key.lowercased().contains("secret") {
                if let stringValue = value as? String, stringValue.count > 8 {
                    formatted[key] = String(stringValue.prefix(4)) + "..." + String(stringValue.suffix(4))
                } else {
                    formatted[key] = "***"
                }
            } else {
                formatted[key] = truncateAny(value, maxLength: maxLength)
            }
        }

        return formatted
    }

    // MARK: - Result Formatting

    /// ツール戻り値を安全にログ用に整形する
    ///
    /// - Parameters:
    ///   - result: ツール戻り値
    ///   - maxLength: 最大長（デフォルト: 2000）
    /// - Returns: ログ用に整形された情報を含む辞書
    public static func formatResult(
        _ result: Any,
        maxLength: Int = defaultMaxLength
    ) -> [String: Any] {
        var info: [String: Any] = [:]

        // 結果のサイズを計算
        if let dict = result as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                info["result_size_bytes"] = data.count
                info["truncated"] = data.count > maxLength

                // 切り詰めたJSONを含める
                let jsonString = String(data: data, encoding: .utf8) ?? "{}"
                info["result"] = truncate(jsonString, maxLength: maxLength)
            }
        } else if let array = result as? [Any] {
            if let data = try? JSONSerialization.data(withJSONObject: array) {
                info["result_size_bytes"] = data.count
                info["truncated"] = data.count > maxLength
                info["result_count"] = array.count
            }
        } else {
            let stringValue = String(describing: result)
            info["result"] = truncate(stringValue, maxLength: maxLength)
            info["truncated"] = stringValue.count > maxLength
        }

        return info
    }
}
