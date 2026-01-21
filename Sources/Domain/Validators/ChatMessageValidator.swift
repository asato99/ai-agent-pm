// Sources/Domain/Validators/ChatMessageValidator.swift
// Phase 0: チャットメッセージのバリデーションロジック
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md

import Foundation

/// チャットメッセージのバリデーションを行うユーティリティ
public enum ChatMessageValidator {

    // MARK: - 定数

    /// メッセージ本文の最大文字数
    public static let maxContentLength = 4000

    /// REST APIのデフォルト取得件数
    public static let defaultLimit = 50

    /// REST APIの最大取得件数
    public static let maxLimit = 200

    // MARK: - コンテンツバリデーション

    /// メッセージコンテンツのバリデーション結果
    public enum ContentValidationResult: Equatable {
        case valid
        case invalid(ContentValidationError)
    }

    /// コンテンツバリデーションエラー
    public enum ContentValidationError: Equatable {
        case emptyContent
        case contentTooLong(maxLength: Int, actualLength: Int)
    }

    /// メッセージコンテンツをバリデートする
    /// - Parameter content: バリデート対象のコンテンツ
    /// - Returns: バリデーション結果
    public static func validate(content: String) -> ContentValidationResult {
        // 空白をトリムした後に空かどうかチェック
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .invalid(.emptyContent)
        }

        // 文字数制限チェック（トリム前の長さでチェック）
        if content.count > maxContentLength {
            return .invalid(.contentTooLong(maxLength: maxContentLength, actualLength: content.count))
        }

        return .valid
    }

    // MARK: - limit パラメータバリデーション

    /// limitパラメータのバリデーション結果
    public enum LimitValidationResult: Equatable {
        /// 有効な値
        case valid(Int)
        /// 最大値に制限された
        case clamped(Int)
        /// デフォルト値を使用
        case useDefault(Int)

        /// 実際に使用する値を取得
        public var effectiveValue: Int {
            switch self {
            case let .valid(value): return value
            case let .clamped(value): return value
            case let .useDefault(value): return value
            }
        }
    }

    /// limitパラメータをバリデートする
    /// - Parameter limit: バリデート対象のlimit値（nilの場合はデフォルト値を返す）
    /// - Returns: バリデーション結果
    public static func validateLimit(_ limit: Int?) -> LimitValidationResult {
        guard let limit = limit, limit > 0 else {
            return .useDefault(defaultLimit)
        }

        if limit > maxLimit {
            return .clamped(maxLimit)
        }

        return .valid(limit)
    }
}
