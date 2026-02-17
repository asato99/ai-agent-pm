// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Agent API

extension MCPServer {

    // MARK: Phase 4: Agent API

    /// get_my_task - 認証済みエージェントの現在のタスクを取得
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Phase 4: projectId でフィルタリング（同一エージェントが複数プロジェクトで同時稼働可能）
    func getMyTask(session: AgentSession) throws -> [String: Any] {
        let agentId = session.agentId.value
        let projectId = session.projectId.value
        Self.log("[MCP] getMyTask called for agent: '\(agentId)', project: '\(projectId)'")

        let id = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // Phase 4: in_progress 状態のタスクを該当プロジェクトでフィルタリング
        let tasks = try taskRepository.findByAssignee(id)
        let inProgressTasks = tasks.filter { $0.status == .inProgress && $0.projectId == projId }

        if let task = inProgressTasks.first {
            // タスクのコンテキストを取得
            let latestContext = try contextRepository.findLatest(taskId: task.id)

            // ハンドオフ情報を取得
            let handoffs = try handoffRepository.findByTask(task.id)
            let latestHandoff = handoffs.last

            // Note: working_directoryはコーディネーターが管理するため、
            // get_my_taskでは返さない（エージェントの混乱を防ぐ）

            var taskDict: [String: Any] = [
                "task_id": task.id.value,
                "title": task.title,
                "description": task.description ?? ""
            ]

            // ワークフロー指示を追加（Agent が description を直接実行せず、get_next_action に従うよう誘導）
            taskDict["workflow_instruction"] = """
                このタスク情報はコンテキスト理解用です。実際の作業を開始する前に、
                必ず get_next_action を呼び出して、システムからの指示に従ってください。
                タスクはサブタスクに分解してから実行する必要があります。
                """

            if let ctx = latestContext {
                taskDict["context"] = contextToDict(ctx)
            }

            if let handoff = latestHandoff {
                taskDict["handoff"] = handoffToDict(handoff)
            }

            // Phase 4: 実行ログを自動作成（report_execution_startの代替）
            var executionLog = ExecutionLog(
                taskId: task.id,
                agentId: id,
                startedAt: Date()
            )

            // セッションに既に model info がある場合は ExecutionLog にコピー
            // （report_model が get_my_task より先に呼ばれた場合）
            if session.modelVerified != nil {
                executionLog.setModelInfo(
                    provider: session.reportedProvider ?? "",
                    model: session.reportedModel ?? "",
                    verified: session.modelVerified ?? false
                )
                Self.log("[MCP] ExecutionLog: Copying model info from session")
            }

            try executionLogRepository.save(executionLog)
            Self.log("[MCP] ExecutionLog auto-created: \(executionLog.id.value)")

            // ワークフローフェーズを記録（get_next_action用）
            // 参照: docs/plan/STATE_DRIVEN_WORKFLOW.md
            // Note: Context.sessionId は sessions テーブルを参照するため、
            // 先に Session を作成してからその ID を使用する
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: projId,
                agentId: id,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)
            Self.log("[MCP] Workflow session created: \(workflowSession.id.value)")

            let workflowContext = Context(
                id: ContextID.generate(),
                taskId: task.id,
                sessionId: workflowSession.id,
                agentId: id,
                progress: "workflow:task_fetched"
            )
            try contextRepository.save(workflowContext)
            Self.log("[MCP] Workflow phase recorded: task_fetched")

            Self.log("[MCP] getMyTask returning task: \(task.id.value)")

            return [
                "success": true,
                "has_task": true,
                "task": taskDict,
                "instruction": """
                    タスクが割り当てられています。
                    get_next_action を呼び出してください。
                    システムが次の作業を指示します。
                    """
            ]
        } else {
            Self.log("[MCP] getMyTask: No in_progress task for agent '\(agentId)' in project '\(projectId)'")

            return [
                "success": true,
                "has_task": false,
                "instruction": "現在割り当てられたタスクはありません"
            ]
        }
    }

    /// get_my_task_progress - タスク進行状況確認（読み取り専用）
    /// 副作用なし: ログ書き込みやセッション作成は行わない
    /// 参照: docs/plan/GET_MY_TASK_PROGRESS.md
    func getMyTaskProgress(session: AgentSession) throws -> [String: Any] {
        let agentId = session.agentId
        let projectId = session.projectId
        Self.log("[MCP] getMyTaskProgress called for agent: '\(agentId.value)', project: '\(projectId.value)'")

        // エージェントに割り当てられた全タスクを取得
        let allTasks = try taskRepository.findByAssignee(agentId)

        // 対象プロジェクト内のタスクのみ抽出
        let projectTasks = allTasks.filter { $0.projectId == projectId }

        // 親タスク（parent_task_id が nil）と子タスクに分類
        let parentTasks = projectTasks.filter { $0.parentTaskId == nil }

        // 結果を構造化
        var tasksList: [[String: Any]] = []

        for parentTask in parentTasks {
            // このタスクのサブタスクを取得
            let subTasks = projectTasks.filter { $0.parentTaskId == parentTask.id }

            var taskDict: [String: Any] = [
                "id": parentTask.id.value,
                "title": parentTask.title,
                "status": parentTask.status.rawValue
            ]

            if !subTasks.isEmpty {
                taskDict["subtasks"] = subTasks.map { subTask in
                    [
                        "id": subTask.id.value,
                        "title": subTask.title,
                        "status": subTask.status.rawValue
                    ] as [String: Any]
                }
            }

            tasksList.append(taskDict)
        }

        return [
            "tasks": tasksList
        ]
    }

    /// get_notifications - エージェントの未読通知を取得
    /// 参照: docs/design/NOTIFICATION_SYSTEM.md
    func getNotifications(
        agentId: AgentID,
        projectId: ProjectID,
        markAsRead: Bool
    ) throws -> [String: Any] {
        Self.log("[MCP] getNotifications called for agent: '\(agentId.value)', project: '\(projectId.value)', markAsRead: \(markAsRead)")

        let useCase = GetNotificationsUseCase(notificationRepository: notificationRepository)
        let notifications = try useCase.execute(
            agentId: agentId,
            projectId: projectId,
            markAsRead: markAsRead
        )

        let notificationDicts: [[String: Any]] = notifications.map { notification in
            var dict: [String: Any] = [
                "id": notification.id.value,
                "type": notification.type.rawValue,
                "action": notification.action,
                "message": notification.message,
                "instruction": notification.instruction,
                "created_at": ISO8601DateFormatter().string(from: notification.createdAt)
            ]
            if let taskId = notification.taskId {
                dict["task_id"] = taskId.value
            }
            return dict
        }

        return [
            "success": true,
            "count": notifications.count,
            "notifications": notificationDicts
        ]
    }

    /// report_model - Agent Instanceのモデル情報を申告・検証
    /// Agent Instanceが申告した provider/model_id をエージェント設定と照合し、
    /// 検証結果をセッションに記録する
    func reportModel(
        session: AgentSession,
        provider: String,
        modelId: String
    ) throws -> [String: Any] {
        Self.log("[MCP] reportModel called: provider='\(provider)', model_id='\(modelId)'")

        // エージェント情報を取得（aiType との照合用）
        guard let agent = try agentRepository.findById(session.agentId) else {
            Self.log("[MCP] reportModel: Agent not found: \(session.agentId.value)")
            return [
                "success": false,
                "error": "agent_not_found",
                "message": "エージェントが見つかりません"
            ]
        }

        // 期待値との照合
        var verified = false
        var verificationMessage = ""

        if let expectedAiType = agent.aiType {
            // エージェントにAIType設定がある場合、照合
            let expectedProvider = expectedAiType.provider
            let expectedModelId = expectedAiType.modelId

            if provider == expectedProvider && (modelId == expectedModelId || modelId.hasPrefix(expectedModelId)) {
                verified = true
                verificationMessage = "モデル検証成功: 期待通りのモデルが使用されています"
            } else if provider == expectedProvider {
                // プロバイダーは一致、モデルIDが異なる
                verified = false
                verificationMessage = "モデル不一致: プロバイダーは一致しますが、モデルIDが異なります（期待: \(expectedModelId), 申告: \(modelId)）"
            } else {
                verified = false
                verificationMessage = "モデル不一致: プロバイダーが異なります（期待: \(expectedProvider), 申告: \(provider)）"
            }
        } else {
            // AIType設定がない場合（custom または未設定）
            // 申告を受け入れ、記録のみ行う
            verified = true
            verificationMessage = "モデル申告記録: エージェントにAIType設定がないため、申告を記録しました"
        }

        // セッションを更新
        var updatedSession = session
        updatedSession.reportedProvider = provider
        updatedSession.reportedModel = modelId
        updatedSession.modelVerified = verified
        updatedSession.modelVerifiedAt = Date()

        try agentSessionRepository.save(updatedSession)
        Self.log("[MCP] reportModel: Session updated with verification result: verified=\(verified)")

        // 実行中のExecutionLogにもモデル情報を記録
        // in_progress タスクを取得し、対応するExecutionLogを更新
        let tasks = try taskRepository.findByAssignee(session.agentId)
        if let inProgressTask = tasks.first(where: { $0.status == .inProgress && $0.projectId == session.projectId }) {
            if var executionLog = try executionLogRepository.findLatestByAgentAndTask(
                agentId: session.agentId,
                taskId: inProgressTask.id
            ) {
                executionLog.setModelInfo(provider: provider, model: modelId, verified: verified)
                try executionLogRepository.save(executionLog)
                Self.log("[MCP] reportModel: ExecutionLog updated with model info: \(executionLog.id.value)")
            }
        }

        return [
            "success": true,
            "verified": verified,
            "message": verificationMessage,
            "instruction": verified
                ? "モデル検証が完了しました。get_next_action を呼び出して次の指示を受けてください。"
                : "モデルが期待と異なりますが、処理を続行できます。get_next_action を呼び出して次の指示を受けてください。"
        ]
    }

    /// report_completed - タスク完了を報告
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Phase 4: セッション終了処理を追加
    /// Phase 4: projectId でタスクをフィルタリング（同一エージェントが複数プロジェクトで同時稼働可能）
    func reportCompleted(
        agentId: String,
        projectId: String,
        sessionToken: String,
        result: String,
        summary: String?,
        nextSteps: String?
    ) throws -> [String: Any] {
        Self.log("[MCP] reportCompleted called for agent: '\(agentId)', project: '\(projectId)', result: '\(result)'")
        Self.log("[MCP] reportCompleted: Fetching assigned tasks...")

        let id = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // Phase 4: in_progress 状態のタスクを該当プロジェクトでフィルタリング
        let allAssignedTasks = try taskRepository.findByAssignee(id)
        Self.log("[MCP] reportCompleted: Found \(allAssignedTasks.count) assigned tasks for agent '\(agentId)'")
        for t in allAssignedTasks {
            Self.log("[MCP] reportCompleted:   - \(t.id.value) status=\(t.status.rawValue) project=\(t.projectId.value) parent=\(t.parentTaskId?.value ?? "nil")")
        }
        let inProgressTasks = allAssignedTasks.filter { $0.status == .inProgress && $0.projectId == projId }
        Self.log("[MCP] reportCompleted: Found \(inProgressTasks.count) in_progress tasks in project '\(projectId)'")

        // UC010: result='blocked' で呼び出され、タスクが既に blocked かつ in_progress タスクがない場合は成功
        // これは、ユーザーがUIでステータスを変更し、エージェントが通知を受けて完了報告する場合
        // 注意: in_progress タスクがある場合は早期リターンせず通常フローで処理する
        //       （子タスクが blocked でも親タスクが in_progress なら親を blocked に更新する必要がある）
        // 参照: docs/design/NOTIFICATION_SYSTEM.md
        if result == "blocked" {
            let blockedTasks = allAssignedTasks.filter { $0.status == .blocked && $0.projectId == projId }
            if let blockedTask = blockedTasks.first, inProgressTasks.isEmpty {
                Self.log("[MCP] reportCompleted: Task already blocked (UC010 interrupt flow). Task: \(blockedTask.id.value)")

                // 重要: 早期リターンの前に実行ログを完了させる
                // これをスキップすると、Coordinatorが実行中のログを検出してタスクが終了しない
                let runningLogs = try executionLogRepository.findRunning(agentId: id)
                Self.log("[MCP] reportCompleted (blocked early exit): Completing \(runningLogs.count) running execution logs")
                for var executionLog in runningLogs {
                    let duration = Date().timeIntervalSince(executionLog.startedAt)
                    executionLog.complete(
                        exitCode: 1,  // blocked = error exit
                        durationSeconds: duration,
                        logFilePath: nil,
                        errorMessage: "Task was blocked by user"
                    )
                    try executionLogRepository.save(executionLog)
                    Self.log("[MCP] ExecutionLog completed (blocked): \(executionLog.id.value)")
                }

                return [
                    "success": true,
                    "task_id": blockedTask.id.value,
                    "status": "blocked",
                    "message": "タスクは既に中断されています。作業を終了してください。",
                    "instruction": "logout を呼び出してセッションを終了してください。"
                ]
            }
        }

        guard var task = inProgressTasks.first else {
            Self.log("[MCP] reportCompleted: No in_progress task for agent '\(agentId)' in project '\(projectId)'")
            return [
                "success": false,
                "error": "No in_progress task found for this agent"
            ]
        }

        // Worker（parentTaskId != nil）の場合、すべてのin_progressタスクを完了させる
        // これはManagerが複数のサブタスクを同じWorkerに割り当てた場合に対応
        let additionalInProgressTasks = inProgressTasks.dropFirst()

        // Workerに割り当てられた未着手（todo）タスクも収集（後で完了させる）
        let pendingTodoTasks = allAssignedTasks.filter { $0.status == .todo && $0.projectId == projId && $0.parentTaskId != nil }

        // サブタスク作成を強制: メインタスク（parentTaskId=nil）の場合、サブタスクが必要
        if task.parentTaskId == nil {
            let allTasks = try taskRepository.findByProject(projId, status: nil)
            let subTasks = allTasks.filter { $0.parentTaskId == task.id }
            if subTasks.isEmpty {
                Self.log("[MCP] reportCompleted: Subtasks required for main task. Task: \(task.id.value)")
                return [
                    "success": false,
                    "error": "サブタスクを作成してから完了報告してください。get_next_action を呼び出して指示に従ってください。",
                    "instruction": "get_next_action を呼び出してください。システムがサブタスク作成を指示します。"
                ]
            }

            // 全サブタスクが完了していることを確認
            let incompleteSubTasks = subTasks.filter { $0.status != TaskStatus.done && $0.status != TaskStatus.cancelled }
            if !incompleteSubTasks.isEmpty {
                Self.log("[MCP] reportCompleted: Incomplete subtasks exist. Count: \(incompleteSubTasks.count)")
                return [
                    "success": false,
                    "error": "未完了のサブタスクがあります。全てのサブタスクを完了してから報告してください。",
                    "incomplete_subtasks": incompleteSubTasks.map { ["id": $0.id.value, "title": $0.title, "status": $0.status.rawValue] }
                ]
            }
        }

        // 結果に基づいてステータスを更新
        let newStatus: TaskStatus
        switch result {
        case "success":
            newStatus = .done
        case "failed":
            newStatus = .blocked
        case "blocked":
            newStatus = .blocked
        default:
            Self.log("[MCP] reportCompleted: Invalid result '\(result)'")
            return [
                "success": false,
                "error": "Invalid result value. Use 'success', 'failed', or 'blocked'"
            ]
        }

        let previousStatus = task.status
        task.status = newStatus
        task.updatedAt = Date()
        // Bug fix: statusChangedByAgentIdとstatusChangedAtを設定
        // これにより、誰がステータスを変更したかを追跡可能にする
        task.statusChangedByAgentId = id
        task.statusChangedAt = Date()
        // 完了結果とサマリーをタスクに保存
        task.completionResult = result
        task.completionSummary = summary
        if newStatus == .done {
            task.completedAt = Date()
        }

        try taskRepository.save(task)

        // ワーカーがブロック報告した場合、タスク階層を遡って
        // 最も近い「別エージェント」の祖先タスク（マネージャー）のコンテキストを更新
        // 親の親など入れ子的にタスクが存在しても正しく動作する
        if newStatus == .blocked {
            var currentTask = task
            while let parentId = currentTask.parentTaskId {
                guard let parentTask = try taskRepository.findById(parentId) else {
                    Self.log("[MCP] reportCompleted: Parent task \(parentId.value) not found, stopping hierarchy walk")
                    break
                }

                guard let parentAssigneeId = parentTask.assigneeId else {
                    Self.log("[MCP] reportCompleted: Parent task \(parentId.value) has no assignee, stopping hierarchy walk")
                    break
                }

                if parentAssigneeId != id {
                    // 別エージェントの祖先タスクを発見 → マネージャーに通知
                    let parentLatestContext = try contextRepository.findLatest(taskId: parentId)
                    if parentLatestContext?.progress == "workflow:waiting_for_workers" {
                        if let parentSession = try sessionRepository.findActiveByAgentAndProject(
                            agentId: parentAssigneeId,
                            projectId: projId
                        ).first {
                            let parentContext = Context(
                                id: ContextID.generate(),
                                taskId: parentId,
                                sessionId: parentSession.id,
                                agentId: parentAssigneeId,
                                progress: "workflow:worker_blocked",
                                findings: nil,
                                blockers: "Subtask \(task.id.value) blocked: \(summary ?? "no reason")",
                                nextSteps: nil
                            )
                            try contextRepository.save(parentContext)
                            Self.log("[MCP] reportCompleted: Walked hierarchy and notified manager '\(parentAssigneeId.value)' via ancestor task \(parentId.value)")
                        } else {
                            Self.log("[MCP] reportCompleted: No active session for ancestor manager '\(parentAssigneeId.value)', skipping context update")
                        }
                    } else {
                        Self.log("[MCP] reportCompleted: Ancestor task \(parentId.value) not in waiting_for_workers state (progress=\(parentLatestContext?.progress ?? "nil")), skipping context update")
                    }
                    break
                }

                // 同じエージェントの祖先タスク → さらに上に遡る
                Self.log("[MCP] reportCompleted: Parent \(parentId.value) assigned to same agent, walking up hierarchy")
                currentTask = parentTask
            }
        }

        // コンテキストを保存（サマリーや次のステップがあれば）
        // Bug fix: 有効なワークフローセッションを検索してそのIDを使用
        // SessionID.generate()は外部キー制約違反を引き起こすため使用しない
        if summary != nil || nextSteps != nil {
            if let activeSession = try sessionRepository.findActiveByAgentAndProject(
                agentId: id,
                projectId: projId
            ).first {
                let context = Context(
                    id: ContextID.generate(),
                    taskId: task.id,
                    sessionId: activeSession.id,
                    agentId: id,
                    progress: summary,
                    findings: nil,
                    blockers: result == "blocked" ? summary : nil,
                    nextSteps: nextSteps
                )
                try contextRepository.save(context)
            } else {
                Self.log("[MCP] reportCompleted: Skipped context creation - no active workflow session")
            }
        }

        // イベントを記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .statusChanged,
            agentId: id,
            sessionId: nil,
            previousState: previousStatus.rawValue,
            newState: newStatus.rawValue,
            reason: summary
        )
        try eventRepository.save(event)

        // Phase 4: セッションを無効化（削除）
        // AgentSession（認証トークン）を削除
        try agentSessionRepository.deleteByToken(sessionToken)
        Self.log("[MCP] reportCompleted: AgentSession invalidated for agent '\(agentId)'")

        // ワークフローSession（作業セッション）も終了
        let sessionStatus: SessionStatus = (result == "success") ? .completed : .abandoned
        let endSessionsUseCase = EndActiveSessionsUseCase(sessionRepository: sessionRepository)
        let endedSessionCount = try endSessionsUseCase.execute(
            agentId: id,
            projectId: projId,
            status: sessionStatus
        )
        Self.log("[MCP] reportCompleted: \(endedSessionCount) workflow session(s) ended for agent '\(agentId)'")

        // Phase 4: 実行ログを完了（report_execution_completeの代替）
        // エージェントの running 状態の実行ログを取得して完了状態に更新
        // Note: findLatestByAgentAndTask(taskId: task.id) は使えない
        //       task.id はワーカーが作成したサブサブタスクの可能性があり、
        //       そのタスクには実行ログがない（実行ログは start_task で作成されるため）
        // Bug fix: 全ての running 状態の実行ログを完了させる
        // 同じエージェントが複数回 start_task を呼び出すと、複数の running ログが存在する可能性がある
        let runningLogs = try executionLogRepository.findRunning(agentId: id)
        Self.log("[MCP] reportCompleted: Found \(runningLogs.count) running execution logs for agent '\(agentId)'")
        for var executionLog in runningLogs {
            let exitCode = result == "success" ? 0 : 1
            let duration = Date().timeIntervalSince(executionLog.startedAt)
            let errorMessage = result != "success" ? summary : nil
            executionLog.complete(
                exitCode: exitCode,
                durationSeconds: duration,
                logFilePath: nil,  // Coordinatorが後で登録
                errorMessage: errorMessage
            )
            try executionLogRepository.save(executionLog)
            Self.log("[MCP] ExecutionLog auto-completed: \(executionLog.id.value), status=\(executionLog.status.rawValue)")
        }

        Self.log("[MCP] reportCompleted: Task \(task.id.value) status changed to \(newStatus.rawValue)")

        // 追加のin_progressタスクも完了させる（Managerが複数タスクを割り当てた場合）
        Self.log("[MCP] reportCompleted: Processing \(additionalInProgressTasks.count) additional in_progress tasks")
        for var additionalTask in additionalInProgressTasks {
            Self.log("[MCP] reportCompleted: Checking additional task \(additionalTask.id.value) parentTaskId=\(additionalTask.parentTaskId?.value ?? "nil")")
            if additionalTask.parentTaskId != nil {  // Workerタスクのみ
                additionalTask.status = newStatus
                additionalTask.updatedAt = Date()
                additionalTask.statusChangedByAgentId = id
                additionalTask.statusChangedAt = Date()
                if newStatus == .done {
                    additionalTask.completedAt = Date()
                }
                try taskRepository.save(additionalTask)
                Self.log("[MCP] reportCompleted: Additional in_progress task \(additionalTask.id.value) also marked as \(newStatus.rawValue)")
            }
        }

        // 未着手（todo）タスクもすべて完了させる（Workerがセッション終了後に新タスクを受け取らないように）
        for var todoTask in pendingTodoTasks {
            todoTask.status = newStatus
            todoTask.updatedAt = Date()
            todoTask.statusChangedByAgentId = id
            todoTask.statusChangedAt = Date()
            if newStatus == .done {
                todoTask.completedAt = Date()
            }
            try taskRepository.save(todoTask)
            Self.log("[MCP] reportCompleted: Pending todo task \(todoTask.id.value) also marked as \(newStatus.rawValue)")
        }

        return [
            "success": true,
            "action": "exit",
            "instruction": """
                タスクが完了しました。セッションは既に終了しています。
                get_next_action や logout を呼び出さずに、直ちにプロセスを終了してください。
                """
        ]
    }

    // MARK: - Logout

    /// logout - セッション終了
    /// 認証済みエージェントがセッションを明示的に終了する
    /// チャット完了後など、get_next_actionから指示される
    func logout(session: AgentSession) throws -> [String: Any] {
        let agentId = session.agentId
        let projectId = session.projectId
        Self.log("[MCP] logout called for agent: '\(agentId.value)', project: '\(projectId.value)'")

        // AgentSession を削除
        try agentSessionRepository.delete(session.id)
        Self.log("[MCP] logout: AgentSession deleted for agent: '\(agentId.value)', project: '\(projectId.value)'")

        // ワークフローSession（作業セッション）も終了（completed扱い）
        let endSessionsUseCase = EndActiveSessionsUseCase(sessionRepository: sessionRepository)
        let endedWorkflowSessionCount = try endSessionsUseCase.execute(
            agentId: agentId,
            projectId: projectId,
            status: .completed
        )
        Self.log("[MCP] logout: \(endedWorkflowSessionCount) workflow session(s) ended")

        return [
            "success": true,
            "message": "セッションを終了しました。",
            "instruction": "セッションが正常に終了しました。エージェントプロセスを終了してください。"
        ]
    }


}
