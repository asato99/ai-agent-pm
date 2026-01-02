// Sources/Domain/Services/AgentKickServiceProtocol.swift
// エージェントキックサービスのプロトコル定義
// 参照: docs/requirements/AGENTS.md - 活動のキック

import Foundation

/// エージェントキック結果
public struct AgentKickResult: Sendable {
    public let success: Bool
    public let agentId: AgentID
    public let agentName: String
    public let message: String?
    public let processId: Int?
    public let timestamp: Date

    public init(
        success: Bool,
        agentId: AgentID,
        agentName: String,
        message: String? = nil,
        processId: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.success = success
        self.agentId = agentId
        self.agentName = agentName
        self.message = message
        self.processId = processId
        self.timestamp = timestamp
    }
}

/// エージェントキックサービスエラー
public enum AgentKickError: Error, Sendable {
    case agentNotFound(AgentID)
    case projectNotFound(ProjectID)
    case workingDirectoryNotSet(ProjectID)
    case workingDirectoryNotFound(String)
    case kickMethodNotSupported(KickMethod)
    case kickCommandNotSet(AgentID)
    case executionFailed(String)
    case taskNotAssigned(TaskID)
    case claudeCLINotFound

    public var localizedDescription: String {
        switch self {
        case .agentNotFound(let id):
            return "Agent not found: \(id.value)"
        case .projectNotFound(let id):
            return "Project not found: \(id.value)"
        case .workingDirectoryNotSet(let id):
            return "Working directory not set for project: \(id.value)"
        case .workingDirectoryNotFound(let path):
            return "Working directory does not exist: \(path)"
        case .kickMethodNotSupported(let method):
            return "Kick method not supported: \(method.rawValue)"
        case .kickCommandNotSet(let id):
            return "Kick command not set for agent: \(id.value)"
        case .executionFailed(let reason):
            return "Kick execution failed: \(reason)"
        case .taskNotAssigned(let id):
            return "Task is not assigned to any agent: \(id.value)"
        case .claudeCLINotFound:
            return "Claude CLI not found. Please install Claude Code or set CLAUDE_CLI_PATH environment variable."
        }
    }
}

/// エージェントキックサービスプロトコル
/// エージェント（Claude Code CLI等）を起動するサービスのインターフェース
public protocol AgentKickServiceProtocol: Sendable {
    /// エージェントをキックする
    /// - Parameters:
    ///   - agent: キックするエージェント
    ///   - task: 実行対象のタスク
    ///   - project: タスクが属するプロジェクト
    /// - Returns: キック結果
    func kick(
        agent: Agent,
        task: Task,
        project: Project
    ) async throws -> AgentKickResult
}
