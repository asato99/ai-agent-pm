// Sources/UseCase/UseCaseError.swift
// UseCase層共通エラー定義

import Foundation
import Domain

// MARK: - UseCase Errors

/// UseCase層で発生するエラー
public enum UseCaseError: Error, Sendable {
    case taskNotFound(TaskID)
    case agentNotFound(AgentID)
    case projectNotFound(ProjectID)
    case sessionNotFound(SessionID)
    case templateNotFound(WorkflowTemplateID)
    case internalAuditNotFound(InternalAuditID)
    case auditRuleNotFound(AuditRuleID)
    case invalidStatusTransition(from: TaskStatus, to: TaskStatus)
    case sessionNotActive
    case sessionAlreadyActive(SessionID)
    case unauthorized
    case validationFailed(String)

    // 認証エラー (Phase 3-1)
    case invalidCredentials
    case credentialNotFound(AgentID)
    case sessionExpired

    // 依存関係ブロック
    case dependencyNotComplete(taskId: TaskID, blockedByTasks: [TaskID])

    // リソース可用性ブロック
    case maxParallelTasksReached(agentId: AgentID, maxParallel: Int, currentCount: Int)

    // 実行ログエラー (Phase 3-3)
    case executionLogNotFound(ExecutionLogID)
    case invalidStateTransition(String)

    // Feature 13: 担当エージェント再割り当て制限
    case reassignmentNotAllowed(taskId: TaskID, status: TaskStatus)

    // Feature 14: プロジェクト一時停止
    case invalidProjectStatus(projectId: ProjectID, currentStatus: ProjectStatus, requiredStatus: String)

    // Task Request/Approval
    case permissionDenied(String)
}

extension UseCaseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .taskNotFound(let id):
            return "Task not found: \(id.value)"
        case .agentNotFound(let id):
            return "Agent not found: \(id.value)"
        case .projectNotFound(let id):
            return "Project not found: \(id.value)"
        case .sessionNotFound(let id):
            return "Session not found: \(id.value)"
        case .templateNotFound(let id):
            return "Workflow template not found: \(id.value)"
        case .internalAuditNotFound(let id):
            return "Internal audit not found: \(id.value)"
        case .auditRuleNotFound(let id):
            return "Audit rule not found: \(id.value)"
        case .invalidStatusTransition(let from, let to):
            return "Invalid status transition: \(from.rawValue) -> \(to.rawValue)"
        case .sessionNotActive:
            return "No active session"
        case .sessionAlreadyActive(let id):
            return "Session already active: \(id.value)"
        case .unauthorized:
            return "Unauthorized operation"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .invalidCredentials:
            return "Invalid agent_id or passkey"
        case .credentialNotFound(let agentId):
            return "Credential not found for agent: \(agentId.value)"
        case .sessionExpired:
            return "Session has expired"
        case .dependencyNotComplete(let taskId, let blockedByTasks):
            let blockedIds = blockedByTasks.map { $0.value }.joined(separator: ", ")
            return "Task \(taskId.value) is blocked by incomplete dependencies: \(blockedIds)"
        case .maxParallelTasksReached(let agentId, let maxParallel, let currentCount):
            return "Agent \(agentId.value) has reached max parallel tasks limit (\(currentCount)/\(maxParallel))"
        case .executionLogNotFound(let id):
            return "Execution log not found: \(id.value)"
        case .invalidStateTransition(let message):
            return "Invalid state transition: \(message)"
        case .reassignmentNotAllowed(let taskId, let status):
            return "Cannot reassign task \(taskId.value) in \(status.rawValue) status"
        case .invalidProjectStatus(let projectId, let currentStatus, let requiredStatus):
            return "Project \(projectId.value) has status '\(currentStatus.rawValue)' but requires '\(requiredStatus)'"
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        }
    }
}
