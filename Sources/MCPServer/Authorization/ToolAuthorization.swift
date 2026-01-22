// Sources/MCPServer/Authorization/ToolAuthorization.swift
// ツール呼び出しの認可制御
// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md

import Foundation
import Domain

// MARK: - Caller Types

/// ツール呼び出し元の種類
enum CallerType {
    /// Coordinator（システム管理者）
    case coordinator
    /// Manager（タスク作成・委任権限）
    case manager(agentId: AgentID, session: AgentSession)
    /// Worker（タスク実行権限）
    case worker(agentId: AgentID, session: AgentSession)
    /// 未認証
    case unauthenticated

    var agentId: AgentID? {
        switch self {
        case .coordinator, .unauthenticated:
            return nil
        case .manager(let agentId, _), .worker(let agentId, _):
            return agentId
        }
    }

    var session: AgentSession? {
        switch self {
        case .coordinator, .unauthenticated:
            return nil
        case .manager(_, let session), .worker(_, let session):
            return session
        }
    }

    var isManager: Bool {
        if case .manager = self { return true }
        return false
    }

    var isWorker: Bool {
        if case .worker = self { return true }
        return false
    }
}

// MARK: - Tool Permission

/// ツールの権限レベル
enum ToolPermission: String {
    /// Coordinator専用（システム管理）
    case coordinatorOnly = "coordinator_only"
    /// Manager専用（タスク作成・委任）
    case managerOnly = "manager_only"
    /// Worker専用（タスク実行完了）
    case workerOnly = "worker_only"
    /// 認証済み（Manager + Worker）
    case authenticated = "authenticated"
    /// 未認証でも呼び出し可能
    case unauthenticated = "unauthenticated"
}

// MARK: - Tool Authorization

/// ツール認可制御
struct ToolAuthorization {

    /// ツール名 → 必要な権限のマッピング
    static let permissions: [String: ToolPermission] = [
        // 未認証でも可能
        "authenticate": .unauthenticated,

        // Coordinator専用
        "health_check": .coordinatorOnly,
        "list_active_projects_with_agents": .coordinatorOnly,
        "get_agent_action": .coordinatorOnly,
        "register_execution_log_file": .coordinatorOnly,
        "invalidate_session": .coordinatorOnly,
        "report_agent_error": .coordinatorOnly,
        "list_managed_agents": .coordinatorOnly,

        // Manager専用
        "list_subordinates": .managerOnly,
        "get_subordinate_profile": .managerOnly,
        "assign_task": .managerOnly,

        // 認証済み共通（Manager + Worker）- サブタスク作成用
        "create_task": .authenticated,  // Workers can create sub-tasks for self-execution
        "create_tasks_batch": .authenticated,  // Batch creation with local dependency references

        // 認証済み共通（Manager + Worker）- タスク完了報告
        // Managerも自分のメインタスクを完了報告する必要がある
        "report_completed": .authenticated,

        // 認証済み共通（Manager + Worker）
        "report_model": .authenticated,
        "get_my_profile": .authenticated,
        "get_my_task": .authenticated,
        "get_notifications": .authenticated,  // 通知取得
        "get_next_action": .authenticated,
        "update_task_status": .authenticated,
        "get_project": .authenticated,
        "list_tasks": .authenticated,
        "get_task": .authenticated,
        "report_execution_start": .authenticated,
        "report_execution_complete": .authenticated,

        // チャット機能（認証済み）- UC009
        // 参照: docs/design/CHAT_FEATURE.md
        "get_pending_messages": .authenticated,
        "respond_chat": .authenticated,
    ]

    /// ツール呼び出しの認可チェック
    /// - Parameters:
    ///   - tool: ツール名
    ///   - caller: 呼び出し元
    /// - Throws: MCPError.permissionDenied if not authorized
    static func authorize(tool: String, caller: CallerType) throws {
        guard let permission = permissions[tool] else {
            // 未定義のツールは拒否
            throw ToolAuthorizationError.toolNotRegistered(tool)
        }

        switch (permission, caller) {
        // 未認証ツール: 誰でもOK
        case (.unauthenticated, _):
            return

        // Coordinator専用
        case (.coordinatorOnly, .coordinator):
            return
        case (.coordinatorOnly, _):
            throw ToolAuthorizationError.coordinatorRequired(tool)

        // Manager専用
        case (.managerOnly, .manager):
            return
        case (.managerOnly, .coordinator):
            throw ToolAuthorizationError.managerRequired(tool)
        case (.managerOnly, .worker):
            throw ToolAuthorizationError.managerRequired(tool)
        case (.managerOnly, .unauthenticated):
            throw ToolAuthorizationError.authenticationRequired(tool)

        // Worker専用
        case (.workerOnly, .worker):
            return
        case (.workerOnly, .coordinator):
            throw ToolAuthorizationError.workerRequired(tool)
        case (.workerOnly, .manager):
            throw ToolAuthorizationError.workerRequired(tool)
        case (.workerOnly, .unauthenticated):
            throw ToolAuthorizationError.authenticationRequired(tool)

        // 認証済み（Manager + Worker）
        case (.authenticated, .manager), (.authenticated, .worker):
            return
        case (.authenticated, .coordinator):
            throw ToolAuthorizationError.authenticationRequired(tool)
        case (.authenticated, .unauthenticated):
            throw ToolAuthorizationError.authenticationRequired(tool)
        }
    }

    /// 指定された権限のツール一覧を取得
    static func tools(for permission: ToolPermission) -> [String] {
        permissions.filter { $0.value == permission }.map { $0.key }
    }
}

// MARK: - Authorization Errors

/// 認可エラー
enum ToolAuthorizationError: Error, LocalizedError {
    case toolNotRegistered(String)
    case coordinatorRequired(String)
    case managerRequired(String)
    case workerRequired(String)
    case authenticationRequired(String)
    case notSubordinate(managerId: String, targetId: String)

    var errorDescription: String? {
        switch self {
        case .toolNotRegistered(let tool):
            return "Tool '\(tool)' is not registered in authorization system"
        case .coordinatorRequired(let tool):
            return "Tool '\(tool)' requires Coordinator privilege"
        case .managerRequired(let tool):
            return "Tool '\(tool)' requires Manager privilege"
        case .workerRequired(let tool):
            return "Tool '\(tool)' requires Worker privilege"
        case .authenticationRequired(let tool):
            return "Tool '\(tool)' requires authentication. Call authenticate first."
        case .notSubordinate(let managerId, let targetId):
            return "Agent '\(targetId)' is not a subordinate of '\(managerId)'"
        }
    }
}
