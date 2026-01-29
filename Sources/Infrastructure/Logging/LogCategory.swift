// Sources/Infrastructure/Logging/LogCategory.swift
// ログカテゴリ定義

import Foundation

/// ログのカテゴリ（機能領域）
///
/// ログをフィルタリングする際の分類に使用。
/// 各カテゴリは特定の機能領域に対応している。
public enum LogCategory: String, Codable, Sendable, CaseIterable {
    /// システム全般（起動、シャットダウン等）
    case system = "system"

    /// ヘルスチェック（定期的な死活確認）
    case health = "health"

    /// 認証・認可
    case auth = "auth"

    /// エージェント関連
    case agent = "agent"

    /// タスク関連
    case task = "task"

    /// チャット・会話関連
    case chat = "chat"

    /// プロジェクト関連
    case project = "project"

    /// MCPツール呼び出し
    case mcp = "mcp"

    /// トランスポート層（stdio, socket等）
    case transport = "transport"

    // MARK: - Display String

    /// 表示用の大文字文字列
    public var displayString: String {
        rawValue.uppercased()
    }
}
