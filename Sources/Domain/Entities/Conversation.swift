// Sources/Domain/Entities/Conversation.swift
// Reference: docs/design/AI_TO_AI_CONVERSATION.md
// Reference: docs/design/TASK_CONVERSATION_AWAIT.md - タスクIDによる会話紐付け
//
// AIエージェント間の会話を管理するエンティティ
// 明示的な会話開始・終了のライフサイクルを提供

import Foundation

/// AIエージェント間の会話
///
/// ## 状態遷移
/// ```
/// pending → active → terminating → ended
///    ↓
/// expired (タイムアウト)
/// ```
///
/// ## 使用例
/// ```swift
/// // 会話を開始
/// let conv = Conversation(
///     projectId: projectId,
///     initiatorAgentId: agentA,
///     participantAgentId: agentB,
///     purpose: "実装方針の相談"
/// )
/// // state は .pending で開始
/// ```
public struct Conversation: Identifiable, Codable, Sendable, Equatable {
    /// 会話ID
    public let id: ConversationID
    /// プロジェクトID
    public let projectId: ProjectID
    /// 紐付くタスクID（ChatDelegation から継承）
    /// 参照: docs/design/TASK_CONVERSATION_AWAIT.md
    public let taskId: TaskID?
    /// 会話を開始したエージェント
    public let initiatorAgentId: AgentID
    /// 会話に招待されたエージェント
    public let participantAgentId: AgentID
    /// 会話の状態
    public var state: ConversationState
    /// 会話の目的（オプション）
    public let purpose: String?
    /// 最大ターン数（1メッセージ = 1ターン）
    /// システム上限: 20、デフォルト: 10
    public let maxTurns: Int
    /// 会話開始日時
    public let createdAt: Date
    /// 会話終了日時
    public var endedAt: Date?

    /// システム上限ターン数（1メッセージ = 1ターン、20往復 = 40ターン）
    public static let systemMaxTurns: Int = 40
    /// デフォルトターン数（10往復 = 20ターン）
    public static let defaultMaxTurns: Int = 20

    public init(
        id: ConversationID = .generate(),
        projectId: ProjectID,
        taskId: TaskID? = nil,
        initiatorAgentId: AgentID,
        participantAgentId: AgentID,
        state: ConversationState = .pending,
        purpose: String? = nil,
        maxTurns: Int = Conversation.defaultMaxTurns,
        createdAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.initiatorAgentId = initiatorAgentId
        self.participantAgentId = participantAgentId
        self.state = state
        self.purpose = purpose
        self.maxTurns = min(maxTurns, Conversation.systemMaxTurns)
        self.createdAt = createdAt
        self.endedAt = endedAt
    }

    /// 指定されたエージェントが会話の参加者かどうか
    /// - Parameter agentId: 確認するエージェントID
    /// - Returns: 参加者であれば true
    public func isParticipant(_ agentId: AgentID) -> Bool {
        initiatorAgentId == agentId || participantAgentId == agentId
    }

    /// 指定されたエージェントの会話相手を取得
    /// - Parameter agentId: 自分のエージェントID
    /// - Returns: 相手のエージェントID、参加者でなければ nil
    public func getPartnerId(for agentId: AgentID) -> AgentID? {
        if agentId == initiatorAgentId {
            return participantAgentId
        } else if agentId == participantAgentId {
            return initiatorAgentId
        }
        return nil
    }
}

/// 会話の状態
public enum ConversationState: String, Codable, Sendable {
    /// 開始要求済み、相手が未参加
    case pending
    /// 両者が参加中
    case active
    /// 終了要求済み、終了通知待ち
    case terminating
    /// 終了完了
    case ended
    /// タイムアウトにより期限切れ
    case expired
}
