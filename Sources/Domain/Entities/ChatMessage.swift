// Sources/Domain/Entities/ChatMessage.swift
// Reference: docs/design/CHAT_FEATURE.md - Section 2.4

import Foundation

/// Chat message entity with dual storage model
/// Each agent stores messages in their own storage file
/// - Sender's storage: includes receiverId
/// - Receiver's storage: receiverId is nil
public struct ChatMessage: Identifiable, Equatable, Sendable, Codable {
    public let id: ChatMessageID
    /// Sender's agent ID
    public let senderId: AgentID
    /// Receiver's agent ID (only in sender's storage)
    public let receiverId: AgentID?
    public let content: String
    public let createdAt: Date

    /// Related task ID (optional)
    public let relatedTaskId: TaskID?
    /// Related handoff ID (optional)
    public let relatedHandoffId: HandoffID?
    /// Related conversation ID (optional, for AI-to-AI conversations)
    /// Reference: docs/design/AI_TO_AI_CONVERSATION.md
    public let conversationId: ConversationID?

    public init(
        id: ChatMessageID,
        senderId: AgentID,
        receiverId: AgentID? = nil,
        content: String,
        createdAt: Date = Date(),
        relatedTaskId: TaskID? = nil,
        relatedHandoffId: HandoffID? = nil,
        conversationId: ConversationID? = nil
    ) {
        self.id = id
        self.senderId = senderId
        self.receiverId = receiverId
        self.content = content
        self.createdAt = createdAt
        self.relatedTaskId = relatedTaskId
        self.relatedHandoffId = relatedHandoffId
        self.conversationId = conversationId
    }

    /// Check if this message was sent by the given agent
    /// - Parameter agentId: Agent ID to check
    /// - Returns: true if senderId matches
    public func isSentBy(_ agentId: AgentID) -> Bool {
        senderId == agentId
    }

    /// Check if this message was received by the given agent
    /// (i.e., the message is from someone else)
    /// - Parameter agentId: Agent ID to check
    /// - Returns: true if senderId does NOT match
    public func isReceivedBy(_ agentId: AgentID) -> Bool {
        senderId != agentId
    }

    /// Create a copy without receiverId (for receiver's storage)
    public func withoutReceiverId() -> ChatMessage {
        ChatMessage(
            id: id,
            senderId: senderId,
            receiverId: nil,
            content: content,
            createdAt: createdAt,
            relatedTaskId: relatedTaskId,
            relatedHandoffId: relatedHandoffId,
            conversationId: conversationId
        )
    }
}

// MARK: - ChatCommandMarker

/// チャットコマンドマーカー
/// チャットメッセージ内の @@コマンド: 形式のマーカーを検出・抽出する
/// 参照: docs/design/CHAT_COMMAND_MARKER.md
public enum ChatCommandMarker {

    // MARK: - 正規表現パターン

    /// タスク作成マーカーパターン: @@タスク作成: または ＠＠タスク作成: (半角・全角混合対応)
    private static let taskCreatePattern = "[@＠][@＠]タスク作成:"

    /// タスク通知マーカーパターン: @@タスク通知: または ＠＠タスク通知: (半角・全角混合対応)
    private static let taskNotifyPattern = "[@＠][@＠]タスク通知:"

    /// タスク調整マーカーパターン: @@タスク調整: または ＠＠タスク調整: (半角・全角混合対応)
    private static let taskAdjustPattern = "[@＠][@＠]タスク調整:"

    // MARK: - マーカー検出

    /// メッセージにタスク作成マーカーが含まれているかチェック
    /// - Parameter content: チェック対象のメッセージ内容
    /// - Returns: @@タスク作成: マーカーが含まれている場合 true
    public static func containsTaskCreateMarker(_ content: String) -> Bool {
        return content.range(of: taskCreatePattern, options: .regularExpression) != nil
    }

    /// メッセージにタスク通知マーカーが含まれているかチェック
    /// - Parameter content: チェック対象のメッセージ内容
    /// - Returns: @@タスク通知: マーカーが含まれている場合 true
    public static func containsTaskNotifyMarker(_ content: String) -> Bool {
        return content.range(of: taskNotifyPattern, options: .regularExpression) != nil
    }

    /// メッセージにタスク調整マーカーが含まれているかチェック
    /// - Parameter content: チェック対象のメッセージ内容
    /// - Returns: @@タスク調整: マーカーが含まれている場合 true
    public static func containsTaskAdjustMarker(_ content: String) -> Bool {
        return content.range(of: taskAdjustPattern, options: .regularExpression) != nil
    }

    // MARK: - 内容抽出

    /// タスク作成マーカーからタスクタイトルを抽出
    /// - Parameter content: マーカーを含むメッセージ内容
    /// - Returns: 抽出されたタスクタイトル、マーカーがない場合は nil
    public static func extractTaskTitle(from content: String) -> String? {
        return extractContent(from: content, pattern: taskCreatePattern)
    }

    /// タスク通知マーカーから通知メッセージを抽出
    /// - Parameter content: マーカーを含むメッセージ内容
    /// - Returns: 抽出された通知メッセージ、マーカーがない場合は nil
    public static func extractNotifyMessage(from content: String) -> String? {
        return extractContent(from: content, pattern: taskNotifyPattern)
    }

    /// タスク調整マーカーから調整内容を抽出
    /// - Parameter content: マーカーを含むメッセージ内容
    /// - Returns: 抽出された調整内容、マーカーがない場合は nil
    public static func extractAdjustContent(from content: String) -> String? {
        return extractContent(from: content, pattern: taskAdjustPattern)
    }

    // MARK: - Private

    /// 指定されたパターン以降のテキストを抽出
    private static func extractContent(from content: String, pattern: String) -> String? {
        guard let range = content.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        let afterMarker = content[range.upperBound...]
        let extracted = String(afterMarker).trimmingCharacters(in: .whitespaces)

        return extracted.isEmpty ? nil : extracted
    }
}
