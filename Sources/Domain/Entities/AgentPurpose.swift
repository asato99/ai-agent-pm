// Sources/Domain/Entities/AgentPurpose.swift
// 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md

import Foundation

/// エージェントセッションの目的（起動理由）
/// - task: タスク実行のためのセッション
/// - chat: チャット応答のためのセッション
public enum AgentPurpose: String, Codable, Equatable, Sendable {
    case task = "task"
    case chat = "chat"
}
