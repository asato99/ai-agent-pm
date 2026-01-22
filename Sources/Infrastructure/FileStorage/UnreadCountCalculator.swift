// Sources/Infrastructure/FileStorage/UnreadCountCalculator.swift
// 未読メッセージカウント計算ユーティリティ
// Reference: docs/design/CHAT_FEATURE.md

import Foundation
import Domain

/// 未読メッセージのカウントを計算するユーティリティ
///
/// 未読の定義（人間向け）:
/// - 最後の既読時刻より後に送信された他者からのメッセージ
/// - 既読時刻がない場合は、最後の自分の応答より後に送信されたメッセージ
/// - senderId == agentId のメッセージは自分が送信したもの
/// - senderId != agentId のメッセージは他者から受信したもの
public enum UnreadCountCalculator {

    /// 送信者ごとの未読メッセージ数を計算する（既読時刻を考慮）
    ///
    /// - Parameters:
    ///   - messages: 全メッセージ（時系列順）
    ///   - agentId: 自分のエージェントID（未読判定の基準）
    ///   - lastReadTimes: 送信者ID -> 最終既読時刻 のマッピング
    /// - Returns: 送信者ID -> 未読メッセージ数 のマッピング
    public static func calculateBySender(
        _ messages: [ChatMessage],
        agentId: AgentID,
        lastReadTimes: [String: Date] = [:]
    ) -> [String: Int] {
        guard !messages.isEmpty else { return [:] }

        // 送信者ごとにグループ化
        var messagesBySender: [String: [ChatMessage]] = [:]
        for message in messages where message.senderId != agentId {
            let senderId = message.senderId.value
            messagesBySender[senderId, default: []].append(message)
        }

        var counts: [String: Int] = [:]

        for (senderId, senderMessages) in messagesBySender {
            // この送信者の既読時刻を取得
            let lastReadTime = lastReadTimes[senderId]

            // 最後の自分の応答時刻を取得（この送信者への返信として）
            let lastMyResponseTime = messages
                .filter { $0.senderId == agentId }
                .last?.createdAt

            // 基準時刻を決定（既読時刻 > 最終返信時刻 の新しい方）
            let cutoffTime: Date?
            if let readTime = lastReadTime, let responseTime = lastMyResponseTime {
                cutoffTime = max(readTime, responseTime)
            } else {
                cutoffTime = lastReadTime ?? lastMyResponseTime
            }

            // 基準時刻より後のメッセージをカウント
            let unreadCount: Int
            if let cutoff = cutoffTime {
                unreadCount = senderMessages.filter { $0.createdAt > cutoff }.count
            } else {
                // 基準時刻がない場合、全てのメッセージが未読
                unreadCount = senderMessages.count
            }

            if unreadCount > 0 {
                counts[senderId] = unreadCount
            }
        }

        return counts
    }

    /// 未読メッセージの合計数を計算する
    ///
    /// - Parameters:
    ///   - messages: 全メッセージ（時系列順）
    ///   - agentId: 自分のエージェントID（未読判定の基準）
    ///   - lastReadTimes: 送信者ID -> 最終既読時刻 のマッピング
    /// - Returns: 未読メッセージの合計数
    public static func totalUnread(
        _ messages: [ChatMessage],
        agentId: AgentID,
        lastReadTimes: [String: Date] = [:]
    ) -> Int {
        let counts = calculateBySender(messages, agentId: agentId, lastReadTimes: lastReadTimes)
        return counts.values.reduce(0, +)
    }
}
