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
/// 参照: docs/design/TOOL_AUTHORIZATION_ENHANCEMENT.md
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
    /// チャットセッション専用（purpose=chat）
    case chatOnly = "chat_only"
    /// タスクセッション専用（purpose=task）- 将来用
    case taskOnly = "task_only"
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
        "report_process_exit": .coordinatorOnly,
        "report_agent_error": .coordinatorOnly,
        "list_managed_agents": .coordinatorOnly,
        "get_app_settings": .coordinatorOnly,

        // Manager専用
        "list_subordinates": .managerOnly,
        "get_subordinate_profile": .managerOnly,
        "assign_task": .managerOnly,
        "select_action": .managerOnly,  // 次のアクション選択

        // タスクセッション専用 - サブタスク作成用
        "create_task": .taskOnly,  // Workers can create sub-tasks for self-execution
        "create_tasks_batch": .taskOnly,  // Batch creation with local dependency references
        "split_task": .taskOnly,  // Split a task into sibling tasks (creator only, todo/backlog)

        // タスクセッション専用 - タスク完了報告
        "report_completed": .taskOnly,

        // 認証済み共通（Manager + Worker）
        "report_model": .authenticated,
        "get_my_profile": .authenticated,
        "get_my_task": .authenticated,
        "get_my_task_progress": .authenticated,  // タスク進行状況確認（読み取り専用）
        "get_notifications": .authenticated,  // 通知取得
        "get_next_action": .authenticated,
        "update_task_status": .taskOnly,  // タスクセッション専用
        "get_project": .authenticated,
        "list_tasks": .authenticated,
        "get_task": .authenticated,
        "report_execution_start": .taskOnly,  // タスクセッション専用
        "report_execution_complete": .taskOnly,  // タスクセッション専用
        "logout": .authenticated,  // セッション終了

        // チャット機能（チャットセッション専用）- UC009
        // 参照: docs/design/CHAT_FEATURE.md
        // 参照: docs/design/TOOL_AUTHORIZATION_ENHANCEMENT.md
        "get_pending_messages": .chatOnly,

        // メッセージ送信（チャットセッション専用）
        // 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
        // 廃止: docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md
        "send_message": .chatOnly,

        // AI-to-AI会話機能（チャットセッション専用）- UC016
        // 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md
        "start_conversation": .chatOnly,
        "end_conversation": .chatOnly,

        // タスクセッションからチャットセッションへの委譲
        // 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
        // 参照: docs/design/TASK_CONVERSATION_AWAIT.md
        "delegate_to_chat_session": .taskOnly,
        "get_task_conversations": .taskOnly,
        "report_delegation_completed": .chatOnly,

        // タスク依頼・承認機能
        // 参照: docs/design/TASK_REQUEST_APPROVAL.md
        "request_task": .authenticated,          // AIエージェント用（認証済み）
        "approve_task_request": .managerOnly,    // Manager専用（人間）
        "reject_task_request": .managerOnly,     // Manager専用（人間）

        // 自己状況確認機能（認証済み：タスク・チャット両方）
        // 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 2
        "get_my_execution_history": .authenticated,  // 自分の実行履歴取得
        "get_execution_log": .authenticated,         // 実行ログ詳細取得

        // チャット→タスク操作ツール（チャットセッション専用）
        // 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 3
        "start_task_from_chat": .chatOnly,   // 上位者依頼でタスク実行開始
        "update_task_from_chat": .chatOnly,  // 上位者依頼でタスク修正

        // セッション間通知ツール
        // 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 4
        "notify_task_session": .chatOnly,         // チャット→タスクセッションへ通知
        "get_conversation_messages": .taskOnly,   // タスクセッションから会話メッセージ取得

        // ヘルプ・ガイド
        "help": .unauthenticated,
        "get_session_guide": .authenticated,

        // スキル管理（認証済み）
        "register_skill": .authenticated,
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

        // Manager専用（Coordinatorも可）
        // Note: Coordinatorはシステム管理者としてManager権限を包含する
        case (.managerOnly, .manager), (.managerOnly, .coordinator):
            return
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

        // チャットセッション専用（purpose=chat）
        case (.chatOnly, .manager(_, let session)), (.chatOnly, .worker(_, let session)):
            guard session.purpose == .chat else {
                throw ToolAuthorizationError.chatSessionRequired(tool, currentPurpose: session.purpose)
            }
            return
        case (.chatOnly, .coordinator):
            throw ToolAuthorizationError.authenticationRequired(tool)
        case (.chatOnly, .unauthenticated):
            throw ToolAuthorizationError.authenticationRequired(tool)

        // タスクセッション専用（purpose=task）- 将来用
        case (.taskOnly, .manager(_, let session)), (.taskOnly, .worker(_, let session)):
            guard session.purpose == .task else {
                throw ToolAuthorizationError.taskSessionRequired(tool, currentPurpose: session.purpose)
            }
            return
        case (.taskOnly, .coordinator):
            throw ToolAuthorizationError.authenticationRequired(tool)
        case (.taskOnly, .unauthenticated):
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
/// 参照: docs/design/TOOL_AUTHORIZATION_ENHANCEMENT.md
enum ToolAuthorizationError: Error, LocalizedError {
    case toolNotRegistered(String)
    case coordinatorRequired(String)
    case managerRequired(String)
    case workerRequired(String)
    case authenticationRequired(String)
    case notSubordinate(managerId: String, targetId: String)
    /// チャットセッションが必要（purpose=chat）
    case chatSessionRequired(String, currentPurpose: AgentPurpose)
    /// タスクセッションが必要（purpose=task）
    case taskSessionRequired(String, currentPurpose: AgentPurpose)

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
        case .chatSessionRequired(let tool, let currentPurpose):
            return "Tool '\(tool)' requires a chat session (purpose=chat). Current session purpose is '\(currentPurpose.rawValue)'."
        case .taskSessionRequired(let tool, let currentPurpose):
            return "Tool '\(tool)' requires a task session (purpose=task). Current session purpose is '\(currentPurpose.rawValue)'."
        }
    }
}
