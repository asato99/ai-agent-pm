// Sources/Infrastructure/FileStorage/PendingMessageIdentifier.swift
// Phase 0: 未読メッセージ判定ロジック
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md

import Foundation
import Domain

/// 未読（pending）メッセージを特定するユーティリティ
///
/// 未読の定義（senderId/receiverIdモデル）:
/// - 既読時刻が指定されている場合: 既読時刻より後に送信された他者からのメッセージ
/// - 既読時刻がない場合（後方互換）: 最後の自分の応答より後に送信された他者からのメッセージ
/// - senderId == agentId のメッセージは自分が送信したもの
/// - senderId != agentId のメッセージは他者から受信したもの
///
/// Reference: docs/design/CHAT_FEATURE.md - Section 9.11
public enum PendingMessageIdentifier {

    /// MCP用のデフォルトコンテキスト件数
    public static let defaultContextLimit = 20

    /// MCP用のデフォルト未読件数上限
    public static let defaultPendingLimit = 10

    /// 未読メッセージを特定する
    ///
    /// - Parameters:
    ///   - messages: 全メッセージ（時系列順）
    ///   - agentId: 自分のエージェントID（未読判定の基準）
    ///   - lastReadTimes: 送信者ID -> 最終既読時刻 のマッピング（オプション）
    ///   - limit: 返す未読メッセージの最大件数（nilの場合は全件）
    /// - Returns: 未読の受信メッセージ（時系列順）
    public static func identify(
        _ messages: [ChatMessage],
        agentId: AgentID,
        lastReadTimes: [String: Date] = [:],
        limit: Int? = nil
    ) -> [ChatMessage] {
        guard !messages.isEmpty else { return [] }

        let pendingMessages: [ChatMessage]

        if lastReadTimes.isEmpty {
            // 後方互換: 既読時刻がない場合は従来の返信ベースロジック
            pendingMessages = identifyByReply(messages, agentId: agentId)
        } else {
            // 新方式: 既読時刻ベース
            pendingMessages = identifyByLastReadTime(messages, agentId: agentId, lastReadTimes: lastReadTimes)
        }

        // limit が指定されている場合は最新のものに制限
        if let limit = limit, pendingMessages.count > limit {
            return Array(pendingMessages.suffix(limit))
        }

        return pendingMessages
    }

    /// 既読時刻ベースの未読判定
    private static func identifyByLastReadTime(
        _ messages: [ChatMessage],
        agentId: AgentID,
        lastReadTimes: [String: Date]
    ) -> [ChatMessage] {
        messages.filter { message in
            // 自分が送ったメッセージは未読対象外
            guard message.senderId != agentId else { return false }

            // 送信者の既読時刻を取得
            if let lastRead = lastReadTimes[message.senderId.value] {
                // 既読時刻より後のメッセージのみが未読
                return message.createdAt > lastRead
            } else {
                // この送信者からの既読時刻がない場合は未読
                return true
            }
        }
    }

    /// 返信ベースの未読判定（後方互換）
    private static func identifyByReply(
        _ messages: [ChatMessage],
        agentId: AgentID
    ) -> [ChatMessage] {
        // 最後の自分の応答のインデックスを探す
        let lastMyMessageIndex = messages.lastIndex { $0.senderId == agentId }

        if let lastMyMessageIndex = lastMyMessageIndex {
            // 自分の応答より後の他者からのメッセージを取得
            return messages.suffix(from: lastMyMessageIndex + 1)
                .filter { $0.senderId != agentId }
        } else {
            // 自分の応答がない場合、全ての他者からのメッセージが未読
            return messages.filter { $0.senderId != agentId }
        }
    }

    /// コンテキストと未読メッセージを分離して取得する
    ///
    /// MCP `get_pending_messages` 用のメソッド
    ///
    /// - Parameters:
    ///   - messages: 全メッセージ（時系列順）
    ///   - agentId: 自分のエージェントID（未読判定の基準）
    ///   - lastReadTimes: 送信者ID -> 最終既読時刻 のマッピング（オプション）
    ///   - contextLimit: コンテキストとして返す最大件数
    ///   - pendingLimit: 未読として返す最大件数
    /// - Returns: コンテキストと未読メッセージ、および統計情報
    public static func separateContextAndPending(
        _ messages: [ChatMessage],
        agentId: AgentID,
        lastReadTimes: [String: Date] = [:],
        contextLimit: Int = defaultContextLimit,
        pendingLimit: Int = defaultPendingLimit
    ) -> ContextAndPendingResult {
        guard !messages.isEmpty else {
            return ContextAndPendingResult(
                contextMessages: [],
                pendingMessages: [],
                totalHistoryCount: 0,
                contextTruncated: false
            )
        }

        // 未読メッセージを特定（既読時刻を考慮）
        let allPending = identify(messages, agentId: agentId, lastReadTimes: lastReadTimes)
        let limitedPending = Array(allPending.suffix(pendingLimit))

        // コンテキスト = 未読を除いた直近のメッセージ
        let pendingIds = Set(limitedPending.map { $0.id })
        let contextCandidates = messages.filter { !pendingIds.contains($0.id) }
        let contextMessages = Array(contextCandidates.suffix(contextLimit))
        let contextTruncated = contextCandidates.count > contextLimit

        return ContextAndPendingResult(
            contextMessages: contextMessages,
            pendingMessages: limitedPending,
            totalHistoryCount: messages.count,
            contextTruncated: contextTruncated
        )
    }
}

// MARK: - ContextAndPendingResult

/// コンテキストと未読メッセージの分離結果
public struct ContextAndPendingResult: Equatable {
    /// 文脈理解用のメッセージ（直近のやり取り）
    public let contextMessages: [ChatMessage]

    /// 応答対象の未読メッセージ
    public let pendingMessages: [ChatMessage]

    /// 全履歴の件数
    public let totalHistoryCount: Int

    /// コンテキストが切り詰められたかどうか
    public let contextTruncated: Bool

    public init(
        contextMessages: [ChatMessage],
        pendingMessages: [ChatMessage],
        totalHistoryCount: Int,
        contextTruncated: Bool
    ) {
        self.contextMessages = contextMessages
        self.pendingMessages = pendingMessages
        self.totalHistoryCount = totalHistoryCount
        self.contextTruncated = contextTruncated
    }
}
