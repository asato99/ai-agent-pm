// Sources/Domain/Entities/ChatMessage.swift
// 参照: docs/design/CHAT_FEATURE.md - ChatMessageエンティティ

import Foundation

/// チャットメッセージを表すエンティティ
/// エージェントとユーザー間のメッセージ履歴を管理
/// ファイルベース（JSONL形式）で永続化
public struct ChatMessage: Identifiable, Equatable, Sendable, Codable {
    public let id: ChatMessageID
    public let sender: SenderType
    public let content: String
    public let createdAt: Date

    /// 関連タスクID（オプション）
    public let relatedTaskId: TaskID?
    /// 関連ハンドオフID（オプション）
    public let relatedHandoffId: HandoffID?

    public init(
        id: ChatMessageID,
        sender: SenderType,
        content: String,
        createdAt: Date = Date(),
        relatedTaskId: TaskID? = nil,
        relatedHandoffId: HandoffID? = nil
    ) {
        self.id = id
        self.sender = sender
        self.content = content
        self.createdAt = createdAt
        self.relatedTaskId = relatedTaskId
        self.relatedHandoffId = relatedHandoffId
    }

    /// ユーザーからのメッセージかどうか
    public var isFromUser: Bool {
        sender == .user
    }

    /// エージェントからのメッセージかどうか
    public var isFromAgent: Bool {
        sender == .agent
    }
}

// MARK: - SenderType

/// メッセージ送信者の種類
public enum SenderType: String, Codable, Sendable {
    /// 人間ユーザー（PMアプリ操作者）
    case user
    /// AIエージェント
    case agent

    /// 表示用ラベル
    public var displayName: String {
        switch self {
        case .user: return "User"
        case .agent: return "Agent"
        }
    }
}
