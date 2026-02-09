// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Coordinator & Runner API

extension MCPServer {

    // MARK: Phase 4: Runner API

    /// health_check - サーバー起動確認
    /// Runnerが最初に呼び出す。サーバーが応答可能かを確認。
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    func healthCheck() throws -> [String: Any] {
        // TRACEレベル: 頻繁に呼ばれるため、通常は出力しない
        Self.logger.trace("[MCP] healthCheck called", category: .health)

        // DBアクセスの疎通確認
        let agentCount = try agentRepository.findAll().count
        let projectCount = try projectRepository.findAll().count

        return [
            "success": true,
            "status": "ok",
            "agent_count": agentCount,
            "project_count": projectCount
        ]
    }

    /// list_managed_agents - 管理対象エージェント一覧を取得
    /// Runnerがポーリング対象のエージェントIDを取得。詳細は隠蔽。
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    func listManagedAgents() throws -> [String: Any] {
        Self.log("[MCP] listManagedAgents called")

        let agents = try agentRepository.findAll()

        // AIタイプのエージェントのみをRunnerの管理対象とする
        let aiAgents = agents.filter { $0.type == .ai }
        let agentIds = aiAgents.map { $0.id.value }

        Self.log("[MCP] listManagedAgents returning \(agentIds.count) agents")

        return [
            "success": true,
            "agent_ids": agentIds
        ]
    }

    /// get_agent_action - エージェントが取るべきアクションを返す
    /// Runnerはタスクの詳細を知らない。action と reason を返す。
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// 参照: docs/plan/MULTI_AGENT_USE_CASES.md - AIタイプ
    /// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md - 新アーキテクチャ
    /// Phase 4: (agent_id, project_id)単位で判断
    /// action: "start" - エージェントを起動すべき
    ///         "hold" - 起動不要（現状維持）
    ///         "stop" - 停止すべき（将来用）
    ///         "restart" - 再起動すべき（将来用）
    func getAgentAction(agentId: String, projectId: String) throws -> [String: Any] {
        Self.log("[MCP] getAgentAction called for agent: '\(agentId)', project: '\(projectId)'")

        let id = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // エージェントの存在確認
        guard let agent = try agentRepository.findById(id) else {
            Self.log("[MCP] shouldStart: Agent '\(agentId)' not found")
            throw MCPError.agentNotFound(agentId)
        }

        // プロジェクトの存在確認
        guard let project = try projectRepository.findById(projId) else {
            Self.log("[MCP] shouldStart: Project '\(projectId)' not found")
            throw MCPError.projectNotFound(projectId)
        }

        // Feature 14: プロジェクト一時停止チェック
        // pausedプロジェクトではタスク処理を停止（チャット・管理操作は継続）
        if project.status == .paused {
            Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': hold (project is paused)")
            return [
                "action": "hold",
                "reason": "project_paused"
            ]
        }

        // エージェントがプロジェクトに割り当てられているか確認
        let isAssigned = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: id,
            projectId: projId
        )
        if !isAssigned {
            Self.log("[MCP] getAgentAction: Agent '\(agentId)' is not assigned to project '\(projectId)'")
            return [
                "action": "hold",
                "reason": "agent_not_assigned"
            ]
        }

        // UC008: ブロックされたタスクをチェック
        // 該当プロジェクトで該当エージェントにアサインされたblockedタスクがあれば停止
        // ただし、自己ブロック（または下位ワーカーによるブロック）の場合は continue 可能
        // ユーザー（UI）によるブロックは解除不可として stop
        // 参照: docs/plan/BLOCKED_TASK_RECOVERY.md
        let tasks = try taskRepository.findByAssignee(id)

        // in_progressタスクがある場合はblockedタスクの起動チェックをスキップ
        // 複数タスクが割り当てられている場合、実行中タスクを優先
        let hasAnyInProgressTask = tasks.contains { $0.status == .inProgress && $0.projectId == projId }

        // blockedタスクをチェック（in_progressタスクがない場合のみ）
        // blockedタスクがあるだけでは起動しない（holdを返す）
        // in_progressタスクがある場合のみ、そのタスクのために起動する
        let blockedTask = tasks.first { task in
            task.status == .blocked && task.projectId == projId
        }
        if let blocked = blockedTask, !hasAnyInProgressTask {
            // blockedタスクがあるがin_progressタスクがない場合は起動しない
            // マネージャーが下位ワーカーのblocked状態を検知して対処する
            Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': hold (blocked task '\(blocked.id.value)' exists but no in_progress task)")
            return [
                "action": "hold",
                "reason": "blocked_without_in_progress",
                "task_id": blocked.id.value,
                "provider": agent.provider ?? "claude",
                "model": agent.modelId ?? "claude-sonnet-4-5"
            ]
        }

        // Note: Detailed per-task logging removed to reduce log file size
        // (was generating ~1.6M log lines/day with 50+ tasks)

        let inProgressTask = tasks.first { task in
            task.status == .inProgress && task.projectId == projId
        }

        // Log only when there's an in-progress task (reduces log volume)
        if let task = inProgressTask {
            Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': inProgressTask=\(task.id.value)")
        }

        // Manager の待機状態チェック（Context.progress に基づく早期判定）
        if agent.hierarchyType == .manager, let task = inProgressTask {
            let latestContext = try contextRepository.findLatest(taskId: task.id)
            let progress = latestContext?.progress

            // worker_blocked: ワーカーがブロックされた → 即座に起動して対処
            if progress == "workflow:worker_blocked" {
                // スポーン中チェック
                if try checkSpawnInProgress(agentId: id, projectId: projId) {
                    Self.log("[MCP] getAgentAction: Manager has worker_blocked but spawn in progress, holding")
                    return [
                        "action": "hold",
                        "reason": "spawn_in_progress"
                    ]
                }
                try markSpawnStarted(agentId: id, projectId: projId)
                Self.log("[MCP] getAgentAction: Manager has worker_blocked state, starting immediately to handle")
                return [
                    "action": "start",
                    "reason": "worker_blocked",
                    "task_id": task.id.value,
                    "provider": agent.provider ?? "claude",
                    "model": agent.modelId ?? "claude-sonnet-4-5"
                ]
            }

            // handled_blocked: ブロック対処済み、進行中ワーカーなし → 再起動しない
            if progress == "workflow:handled_blocked" {
                Self.log("[MCP] getAgentAction: Manager has handled_blocked state, holding (no restart)")
                return [
                    "action": "hold",
                    "reason": "handled_blocked"
                ]
            }

            // waiting_for_workers: ワーカー完了待ち
            if progress == "workflow:waiting_for_workers" {
                Self.log("[MCP] getAgentAction: Manager is in waiting_for_workers state, checking subtasks")

                // サブタスクの状態を動的に確認
                let allTasks = try taskRepository.findByProject(projId, status: nil)
                let subTasks = allTasks.filter { $0.parentTaskId == task.id }
                let inProgressSubTasks = subTasks.filter { $0.status == .inProgress }
                let completedSubTasks = subTasks.filter { $0.status == .done }

                Self.log("[MCP] getAgentAction: subtasks=\(subTasks.count), inProgress=\(inProgressSubTasks.count), completed=\(completedSubTasks.count)")

                // まだ Worker が実行中 → 起動しない
                if !inProgressSubTasks.isEmpty {
                    Self.log("[MCP] getAgentAction: Manager should hold (waiting for \(inProgressSubTasks.count) workers)")
                    return [
                        "action": "hold",
                        "reason": "waiting_for_workers",
                        "progress": [
                            "completed": completedSubTasks.count,
                            "in_progress": inProgressSubTasks.count,
                            "total": subTasks.count
                        ]
                    ]
                }

                // 全サブタスク完了 → 起動して report_completion (下で処理継続)
                Self.log("[MCP] getAgentAction: All subtasks completed, Manager should start for report_completion")
            }
        }

        // Session Spawn Architecture: WorkDetectionService で仕事判定
        // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md

        // 共通ロジックで仕事の有無を判定
        let hasChatWork = try workDetectionService.hasChatWork(agentId: id, projectId: projId)
        let hasTaskWork = try checkTaskWorkWithHierarchy(agentId: id, projectId: projId, agent: agent)
        let hasWork = hasChatWork || hasTaskWork

        // スポーン中チェック（project_agents.spawn_started_at ベース）
        let spawnInProgress = try checkSpawnInProgress(agentId: id, projectId: projId)

        // Log only when there's work or spawn is in progress (reduces log volume for idle polling)
        if hasWork || spawnInProgress {
            Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': hasChatWork=\(hasChatWork), hasTaskWork=\(hasTaskWork), spawnInProgress=\(spawnInProgress)")
        }

        // 仕事があり、スポーン中でなければ start
        if hasWork && !spawnInProgress {
            try markSpawnStarted(agentId: id, projectId: projId)

            let reason = hasTaskWork ? "has_task_work" : "has_chat_work"
            var result: [String: Any] = [
                "action": "start",
                "reason": reason
            ]

            // task_id を返す（Coordinatorがログファイルパスを登録するため）
            if let task = inProgressTask {
                result["task_id"] = task.id.value
            }

            // provider/model を返す（RunnerがCLIコマンドを選択するため）
            Self.log("[MCP] getAgentAction: agent '\(agentId)' - provider='\(agent.provider ?? "nil")', modelId='\(agent.modelId ?? "nil")'")
            result["provider"] = agent.provider ?? "claude"
            result["model"] = agent.modelId ?? "claude-sonnet-4-5"
            Self.log("[MCP] getAgentAction: returning action='start', reason='\(reason)', provider='\(result["provider"] ?? "nil")', model='\(result["model"] ?? "nil")'")

            return result
        }

        // hold を返す
        let holdReason = spawnInProgress ? "spawn_in_progress" : "no_work"
        // Note: "hold (no_work)" logging removed - it's the most common case and generates excessive logs
        // Only log when there's something notable (spawn in progress)
        if spawnInProgress {
            Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': hold (reason: spawn_in_progress)")
        }
        return [
            "action": "hold",
            "reason": holdReason
        ]
    }

    // MARK: - Session Spawn Architecture Helper Methods
    // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md

    /// タスクワーク判定（階層タイプ別条件を含む）
    /// WorkDetectionService の基本判定 + マネージャー固有の追加条件
    func checkTaskWorkWithHierarchy(agentId: AgentID, projectId: ProjectID, agent: Agent) throws -> Bool {
        // 基本条件（共通ロジック）
        guard try workDetectionService.hasTaskWork(agentId: agentId, projectId: projectId) else {
            return false
        }

        // 階層タイプ別の追加条件
        switch agent.hierarchyType {
        case .manager:
            return try checkManagerTaskWork(agentId: agentId, projectId: projectId)
        case .worker:
            return true  // 基本条件のみ
        }
    }

    /// マネージャーのタスクワーク判定
    /// 部下が仕事中かチェックし、仕事中なら待機
    func checkManagerTaskWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        // 部下が仕事中かチェック
        let allAgents = try agentRepository.findAll()
        let subordinates = allAgents.filter { $0.parentAgentId == agentId }

        for sub in subordinates {
            let hasActiveSession = try agentSessionRepository
                .findByAgentIdAndProjectId(sub.id, projectId: projectId)
                .contains { $0.purpose == .task && $0.expiresAt > Date() }
            if hasActiveSession {
                Self.log("[MCP] checkManagerTaskWork: subordinate '\(sub.id.value)' has active task session, manager should wait")
                return false  // 部下が仕事中
            }
        }

        return true
    }

    /// スポーン中かチェック（project_agents.spawn_started_at ベース）
    /// 120秒以内にスポーン開始されていればスポーン中と判定
    func checkSpawnInProgress(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        guard let assignment = try projectAgentAssignmentRepository.findAssignment(
            agentId: agentId,
            projectId: projectId
        ) else {
            return false
        }

        guard let startedAt = assignment.spawnStartedAt else {
            return false  // NULL = スポーン中でない
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        let spawnTimeout: TimeInterval = 120  // スポーンタイムアウト: 120秒

        if elapsed > spawnTimeout {
            Self.log("[MCP] checkSpawnInProgress: spawn TIMED OUT (elapsed: \(Int(elapsed))s > \(Int(spawnTimeout))s)")
            return false  // タイムアウト = 再スポーン可能
        }

        Self.log("[MCP] checkSpawnInProgress: spawn in progress (elapsed: \(Int(elapsed))s)")
        return true  // スポーン中
    }

    /// スポーン開始をマーク（project_agents.spawn_started_at を更新）
    func markSpawnStarted(agentId: AgentID, projectId: ProjectID) throws {
        Self.log("[MCP] markSpawnStarted: marking spawn started for '\(agentId.value)/\(projectId.value)'")
        try projectAgentAssignmentRepository.updateSpawnStartedAt(
            agentId: agentId,
            projectId: projectId,
            startedAt: Date()
        )
    }

    /// スポーン完了をマーク（project_agents.spawn_started_at をクリア）
    /// authenticate 成功/失敗に関わらず呼び出す → 長期ブロック防止
    func clearSpawnStarted(agentId: AgentID, projectId: ProjectID) throws {
        Self.log("[MCP] clearSpawnStarted: clearing spawn_started_at for '\(agentId.value)/\(projectId.value)'")
        try projectAgentAssignmentRepository.updateSpawnStartedAt(
            agentId: agentId,
            projectId: projectId,
            startedAt: nil
        )
    }



    // MARK: - Coordinator Tools

    // MARK: - Phase 4: Coordinator API（認証不要）

    /// register_execution_log_file - 実行ログにログファイルパスを登録
    /// Coordinatorがプロセス完了後にログファイルパスを登録する際に使用
    /// 認証不要: Coordinatorは認証せずに直接呼び出す
    func registerExecutionLogFile(agentId: String, taskId: String, logFilePath: String) throws -> [String: Any] {
        Self.log("[MCP] registerExecutionLogFile called: agentId='\(agentId)', taskId='\(taskId)', logFilePath='\(logFilePath)'")

        let agId = AgentID(value: agentId)
        let tId = TaskID(value: taskId)

        // 最新の実行ログを取得
        guard var log = try executionLogRepository.findLatestByAgentAndTask(agentId: agId, taskId: tId) else {
            Self.log("[MCP] No execution log found for agent '\(agentId)' and task '\(taskId)'")
            return [
                "success": false,
                "error": "execution_log_not_found"
            ]
        }

        // ログファイルパスを設定して保存
        log.setLogFilePath(logFilePath)
        try executionLogRepository.save(log)

        Self.log("[MCP] ExecutionLog updated with log file path: \(log.id.value)")

        return [
            "success": true,
            "execution_log_id": log.id.value,
            "task_id": log.taskId.value,
            "agent_id": log.agentId.value,
            "log_file_path": logFilePath
        ]
    }

    /// セッションを無効化（Coordinator用）
    /// エージェントプロセス終了時に呼び出され、shouldStartが再度trueを返せるようにする
    func invalidateSession(agentId: String, projectId: String) throws -> [String: Any] {
        Self.log("[MCP] invalidateSession called: agentId='\(agentId)', projectId='\(projectId)'")

        let agId = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // 該当する全セッションを取得して削除
        let sessions = try agentSessionRepository.findByAgentIdAndProjectId(agId, projectId: projId)
        var deletedCount = 0

        for session in sessions {
            try agentSessionRepository.delete(session.id)
            deletedCount += 1
            Self.log("[MCP] Deleted session: \(session.id.value)")
        }

        Self.log("[MCP] invalidateSession completed: deleted \(deletedCount) AgentSession(s)")

        // ワークフローSession（作業セッション）も終了（abandoned扱い）
        let endSessionsUseCase = EndActiveSessionsUseCase(sessionRepository: sessionRepository)
        let endedWorkflowSessionCount = try endSessionsUseCase.execute(
            agentId: agId,
            projectId: projId,
            status: .abandoned
        )
        Self.log("[MCP] invalidateSession: \(endedWorkflowSessionCount) workflow session(s) ended")

        // AI-to-AI会話のクリーンアップ
        // どちらかのエージェントがセッションを抜けた時点で会話は成立しないため、自動終了する
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md
        let endedConversationCount = try cleanupAgentConversations(agentId: agId, projectId: projId)

        return [
            "success": true,
            "agent_id": agentId,
            "project_id": projectId,
            "deleted_agent_sessions": deletedCount,
            "ended_workflow_sessions": endedWorkflowSessionCount,
            "ended_conversations": endedConversationCount
        ]
    }

    /// AI-to-AI会話のクリーンアップ
    /// エージェントがセッションを終了する際、参加中の会話を自動終了する
    /// - Returns: 終了した会話の数
    func cleanupAgentConversations(agentId: AgentID, projectId: ProjectID) throws -> Int {
        // このエージェントが参加しているactive/terminating会話を取得
        let activeConversations = try conversationRepository.findActiveByAgentId(agentId, projectId: projectId)

        var endedCount = 0
        for conversation in activeConversations {
            // initiatorまたはparticipantとして参加している会話を終了
            try conversationRepository.updateState(
                conversation.id,
                state: .ended,
                endedAt: Date()
            )
            let role = conversation.initiatorAgentId == agentId ? "initiator" : "participant"
            Self.log("[MCP] Auto-ended conversation on session invalidation: \(conversation.id.value) (agent was \(role))")
            endedCount += 1
        }

        if endedCount > 0 {
            Self.log("[MCP] invalidateSession: \(endedCount) conversation(s) auto-ended")
        }

        return endedCount
    }

    /// エージェントエラーを報告（Coordinator用）
    /// エージェントプロセスがエラー終了した場合、チャットにエラーメッセージを表示する
    func reportAgentError(agentId: String, projectId: String, errorMessage: String) throws -> [String: Any] {
        Self.log("[MCP] reportAgentError called: agentId='\(agentId)', projectId='\(projectId)', error='\(errorMessage)'")

        let agId = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // エラーメッセージをチャットに保存
        // System error messages use a special "system" senderId, no dual write needed
        let message = ChatMessage(
            id: ChatMessageID(value: "err_\(UUID().uuidString)"),
            senderId: AgentID(value: "system"),
            receiverId: nil,  // System messages don't have a specific receiver
            content: "⚠️ エージェントエラー:\n\(errorMessage)",
            createdAt: Date()
        )

        // System messages are saved only to the agent's storage (no dual write)
        try chatRepository.saveMessage(message, projectId: projId, agentId: agId)
        Self.log("[MCP] Error message saved to chat: \(message.id.value)")

        return [
            "success": true,
            "agent_id": agentId,
            "project_id": projectId,
            "message_id": message.id.value
        ]
    }

    /// アプリケーション設定を取得（Coordinator用）
    /// エージェント起動時にベースプロンプトなどの設定を取得
    func getAppSettings() throws -> [String: Any] {
        Self.log("[MCP] getAppSettings called")

        let settings = try appSettingsRepository.get()

        return [
            "agent_base_prompt": settings.agentBasePrompt as Any,
            "pending_purpose_ttl_seconds": settings.pendingPurposeTTLSeconds,
            "allow_remote_access": settings.allowRemoteAccess
        ]
    }


}
