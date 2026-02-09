// Sources/Domain/Repositories/ChatRepositoryProtocols.swift
// チャット・コミュニケーション関連のリポジトリプロトコル
// （Chat, ChatMessagePage, Conversation, ChatDelegation, Notification）

import Foundation

// MARK: - ChatRepositoryProtocol

/// チャットメッセージリポジトリのプロトコル
/// 参照: docs/design/CHAT_FEATURE.md
/// ファイルベースストレージを想定（.ai-pm/agents/{id}/chat.jsonl）
public protocol ChatRepositoryProtocol: Sendable {
    /// メッセージ一覧を取得（時系列順）
    func findMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage]

    /// メッセージを保存（追記）- 単一ストレージ
    func saveMessage(_ message: ChatMessage, projectId: ProjectID, agentId: AgentID) throws

    /// 最新N件のメッセージを取得
    func getLastMessages(projectId: ProjectID, agentId: AgentID, limit: Int) throws -> [ChatMessage]

    /// 未読メッセージを取得（senderId != agentId のメッセージで、自分の最後のメッセージ以降のもの）
    /// MCP連携用: エージェントが応答すべきメッセージを取得
    func findUnreadMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage]

    // MARK: - 双方向保存（Dual Write）

    /// メッセージを送信者と受信者の両方のストレージに保存
    /// - Parameters:
    ///   - message: 保存するメッセージ（receiverId を含む）
    ///   - projectId: プロジェクトID
    ///   - senderAgentId: 送信者のエージェントID
    ///   - receiverAgentId: 受信者のエージェントID
    /// - Note: 送信者のストレージには receiverId あり、受信者のストレージには receiverId なし
    func saveMessageDualWrite(
        _ message: ChatMessage,
        projectId: ProjectID,
        senderAgentId: AgentID,
        receiverAgentId: AgentID
    ) throws

    // MARK: - ページネーション対応（REST API用）

    /// カーソルベースでメッセージを取得
    /// - Parameters:
    ///   - projectId: プロジェクトID
    ///   - agentId: エージェントID
    ///   - limit: 取得件数上限
    ///   - after: このメッセージIDより後のメッセージを取得
    ///   - before: このメッセージIDより前のメッセージを取得
    /// - Returns: ページネーション結果
    func findMessagesWithCursor(
        projectId: ProjectID,
        agentId: AgentID,
        limit: Int,
        after: ChatMessageID?,
        before: ChatMessageID?
    ) throws -> ChatMessagePage

    /// 総メッセージ数を取得
    func countMessages(projectId: ProjectID, agentId: AgentID) throws -> Int

    // MARK: - 会話ID検索（チャットセッション通知用）

    /// 会話IDでメッセージを検索
    /// タスクセッションがチャットセッション通知を受け取った際に、該当会話のメッセージを取得するために使用
    /// 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 1-2
    /// - Parameters:
    ///   - projectId: プロジェクトID
    ///   - agentId: エージェントID（メッセージを検索するエージェントのストレージ）
    ///   - conversationId: 検索対象の会話ID
    /// - Returns: 該当会話IDを持つメッセージの配列（時系列順）
    func findByConversationId(
        projectId: ProjectID,
        agentId: AgentID,
        conversationId: ConversationID
    ) throws -> [ChatMessage]
}

// MARK: - ChatMessagePage

/// ページネーション結果
public struct ChatMessagePage: Equatable, Sendable {
    /// 取得したメッセージ（時系列順）
    public let messages: [ChatMessage]

    /// さらに前のメッセージがあるか
    public let hasMore: Bool

    /// 総メッセージ数（オプション）
    public let totalCount: Int?

    public init(messages: [ChatMessage], hasMore: Bool, totalCount: Int? = nil) {
        self.messages = messages
        self.hasMore = hasMore
        self.totalCount = totalCount
    }
}

// MARK: - ConversationRepositoryProtocol

/// 会話リポジトリのプロトコル
/// 参照: docs/design/AI_TO_AI_CONVERSATION.md
/// AIエージェント間の会話を管理
public protocol ConversationRepositoryProtocol: Sendable {
    /// 会話を保存
    func save(_ conversation: Conversation) throws

    /// IDで会話を検索
    func findById(_ id: ConversationID) throws -> Conversation?

    /// エージェントが参加しているアクティブな会話を検索（active, terminating状態）
    /// - Parameters:
    ///   - agentId: エージェントID（initiator または participant として）
    ///   - projectId: プロジェクトID
    func findActiveByAgentId(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation]

    /// 参加者として pending な会話を検索
    /// - Parameters:
    ///   - agentId: 参加者のエージェントID
    ///   - projectId: プロジェクトID
    func findPendingForParticipant(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation]

    /// イニシエーターとして pending な会話を検索
    /// 参照: docs/design/AI_TO_AI_CONVERSATION.md - pending状態でもイニシエーターからのメッセージは許可
    /// - Parameters:
    ///   - agentId: イニシエーターのエージェントID
    ///   - projectId: プロジェクトID
    func findPendingForInitiator(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation]

    /// 会話の状態を更新
    func updateState(_ id: ConversationID, state: ConversationState) throws

    /// 会話の状態と終了日時を更新
    func updateState(_ id: ConversationID, state: ConversationState, endedAt: Date?) throws

    /// 最終アクティビティ日時を更新（タイムアウト管理用）
    func updateLastActivity(_ id: ConversationID, at date: Date) throws

    /// 指定したエージェントペア間でアクティブまたはペンディングな会話があるか確認
    func hasActiveOrPendingConversation(
        initiatorAgentId: AgentID,
        participantAgentId: AgentID,
        projectId: ProjectID
    ) throws -> Bool

    /// タスクIDに紐付く会話を検索
    /// get_task_conversations ツールで使用
    /// 参照: docs/design/TASK_CONVERSATION_AWAIT.md
    func findByTaskId(_ taskId: TaskID, projectId: ProjectID) throws -> [Conversation]
}

// MARK: - NotificationRepositoryProtocol

/// 通知リポジトリのプロトコル
/// 参照: docs/design/NOTIFICATION_SYSTEM.md
/// 参照: docs/usecase/UC010_TaskInterruptByStatusChange.md
public protocol NotificationRepositoryProtocol: Sendable {
    /// IDで通知を検索
    func findById(_ id: NotificationID) throws -> AgentNotification?

    /// エージェント×プロジェクトの未読通知を取得（作成日時降順）
    func findUnreadByAgentAndProject(agentId: AgentID, projectId: ProjectID) throws -> [AgentNotification]

    /// 未読通知が存在するか高速チェック（EXISTS句使用）
    func hasUnreadNotifications(agentId: AgentID, projectId: ProjectID) throws -> Bool

    /// 通知を保存
    func save(_ notification: AgentNotification) throws

    /// 通知を既読にマーク
    func markAsRead(_ id: NotificationID) throws

    /// エージェント×プロジェクトの全通知を既読にマーク
    func markAllAsRead(agentId: AgentID, projectId: ProjectID) throws

    /// 指定日数より古い通知を削除（クリーンアップ用）
    /// - Returns: 削除された通知数
    func deleteOlderThan(days: Int) throws -> Int

    /// 全通知数を取得（テスト用）
    func countAll() throws -> Int
}

// MARK: - ChatDelegationRepositoryProtocol

/// チャットセッション委譲リポジトリのプロトコル
/// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
public protocol ChatDelegationRepositoryProtocol: Sendable {
    /// 委譲を保存
    func save(_ delegation: ChatDelegation) throws

    /// IDで委譲を検索
    func findById(_ id: ChatDelegationID) throws -> ChatDelegation?

    /// エージェント×プロジェクトの保留中（pending）委譲を取得
    /// チャットセッション起動時に取得し、processingに更新する
    func findPendingByAgentId(_ agentId: AgentID, projectId: ProjectID) throws -> [ChatDelegation]

    /// エージェント×プロジェクトにpending状態の委譲があるか（高速チェック）
    /// WorkDetectionServiceでの使用を想定
    func hasPending(agentId: AgentID, projectId: ProjectID) throws -> Bool

    /// 委譲のステータスを更新
    func updateStatus(_ id: ChatDelegationID, status: ChatDelegationStatus) throws

    /// 委譲の完了を報告（ステータス、処理日時、結果を更新）
    func markCompleted(_ id: ChatDelegationID, result: String?) throws

    /// 委譲の失敗を報告（ステータス、処理日時、結果を更新）
    func markFailed(_ id: ChatDelegationID, result: String?) throws

    /// 処理中（processing）の委譲を検索
    /// start_conversationでtaskIdを継承するために使用
    /// 参照: docs/design/TASK_CONVERSATION_AWAIT.md
    func findProcessingDelegation(
        agentId: AgentID,
        targetAgentId: AgentID,
        projectId: ProjectID
    ) throws -> ChatDelegation?
}
