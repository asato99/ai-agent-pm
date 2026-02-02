// Sources/Domain/Entities/ChatDelegation.swift
// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
// 参照: docs/design/TASK_CONVERSATION_AWAIT.md - タスクIDによる会話紐付け
//
// タスクセッションからチャットセッションへのコミュニケーション委譲を管理するエンティティ
// タスクセッションは直接メッセージ送信や会話開始ができないため、
// このエンティティを通じてチャットセッションに処理を委譲する

import Foundation

/// チャットセッションへのコミュニケーション委譲
///
/// ## ライフサイクル
/// ```
/// pending → processing → completed
///                    ↘ failed
/// ```
///
/// ## 使用例
/// ```swift
/// // タスクセッションから委譲を作成
/// let delegation = ChatDelegation(
///     agentId: workerA,
///     projectId: projectId,
///     targetAgentId: workerB,
///     purpose: "6往復しりとりをしてほしい"
/// )
/// // status は .pending で開始
///
/// // チャットセッションが取得時に processing に更新
/// // 処理完了後に completed または failed に更新
/// ```
public struct ChatDelegation: Identifiable, Codable, Sendable, Equatable {
    /// 委譲ID
    public let id: ChatDelegationID
    /// 委譲元エージェントID（タスクセッションの所有者）
    public let agentId: AgentID
    /// プロジェクトID
    public let projectId: ProjectID
    /// 移譲元タスクID（タスクセッションから自動設定）
    /// 参照: docs/design/TASK_CONVERSATION_AWAIT.md
    public let taskId: TaskID?
    /// コミュニケーション相手のエージェントID
    public let targetAgentId: AgentID
    /// 依頼内容（何を伝えたいか、何をしてほしいか）
    public let purpose: String
    /// 追加コンテキスト情報（任意）
    public let context: String?
    /// 委譲のステータス
    public var status: ChatDelegationStatus
    /// 作成日時
    public let createdAt: Date
    /// 処理完了日時
    public var processedAt: Date?
    /// 実行結果（JSON文字列）
    public var result: String?

    public init(
        id: ChatDelegationID = .generate(),
        agentId: AgentID,
        projectId: ProjectID,
        taskId: TaskID? = nil,
        targetAgentId: AgentID,
        purpose: String,
        context: String? = nil,
        status: ChatDelegationStatus = .pending,
        createdAt: Date = Date(),
        processedAt: Date? = nil,
        result: String? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.projectId = projectId
        self.taskId = taskId
        self.targetAgentId = targetAgentId
        self.purpose = purpose
        self.context = context
        self.status = status
        self.createdAt = createdAt
        self.processedAt = processedAt
        self.result = result
    }
}

/// 委譲のステータス
public enum ChatDelegationStatus: String, Codable, Sendable {
    /// 保留中（チャットセッションに未取得）
    case pending
    /// 処理中（チャットセッションが取得済み）
    case processing
    /// 完了
    case completed
    /// 失敗
    case failed
}
