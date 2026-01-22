// Sources/Infrastructure/FileStorage/UnreadCountCalculator.swift
// 未読メッセージカウント計算ユーティリティ
// Reference: docs/design/CHAT_FEATURE.md

import Foundation
import Domain

/// 未読メッセージのカウントを計算するユーティリティ
///
/// 未読の定義:
/// - 最後の自分の応答より後に送信された他者からのメッセージ
/// - 自分の応答がない場合は、全ての他者からのメッセージが未読
/// - senderId == agentId のメッセージは自分が送信したもの
/// - senderId != agentId のメッセージは他者から受信したもの
public enum UnreadCountCalculator {

    /// 送信者ごとの未読メッセージ数を計算する
    ///
    /// - Parameters:
    ///   - messages: 全メッセージ（時系列順）
    ///   - agentId: 自分のエージェントID（未読判定の基準）
    /// - Returns: 送信者ID -> 未読メッセージ数 のマッピング
    public static func calculateBySender(_ messages: [ChatMessage], agentId: AgentID) -> [String: Int] {
        guard !messages.isEmpty else { return [:] }

        // 最後の自分の応答のインデックスを探す
        let lastMyMessageIndex = messages.lastIndex { $0.senderId == agentId }

        let pendingMessages: ArraySlice<ChatMessage>

        if let lastMyMessageIndex = lastMyMessageIndex {
            // 自分の応答より後の他者からのメッセージを取得
            pendingMessages = messages.suffix(from: lastMyMessageIndex + 1)
        } else {
            // 自分の応答がない場合、全てのメッセージが候補
            pendingMessages = messages[...]
        }

        // 送信者ごとにカウント（自分のメッセージは除外）
        var counts: [String: Int] = [:]
        for message in pendingMessages where message.senderId != agentId {
            let senderId = message.senderId.value
            counts[senderId, default: 0] += 1
        }

        return counts
    }

    /// 未読メッセージの合計数を計算する
    ///
    /// - Parameters:
    ///   - messages: 全メッセージ（時系列順）
    ///   - agentId: 自分のエージェントID（未読判定の基準）
    /// - Returns: 未読メッセージの合計数
    public static func totalUnread(_ messages: [ChatMessage], agentId: AgentID) -> Int {
        let counts = calculateBySender(messages, agentId: agentId)
        return counts.values.reduce(0, +)
    }
}
