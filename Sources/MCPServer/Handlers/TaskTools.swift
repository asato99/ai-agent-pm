// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Task & Agent Tools

extension MCPServer {

    // MARK: Agent Tools

    /// get_agent_profile - エージェント情報を取得
    func getAgentProfile(agentId: String) throws -> [String: Any] {
        Self.log("[MCP] getAgentProfile called with: '\(agentId)'")

        let id = AgentID(value: agentId)
        guard let agent = try agentRepository.findById(id) else {
            // 見つからない場合、全エージェントをログ
            let allAgents = try? agentRepository.findAll()
            Self.log("[MCP] Agent '\(agentId)' not found. Available: \(allAgents?.map { $0.id.value } ?? [])")
            throw MCPError.agentNotFound(agentId)
        }
        Self.log("[MCP] Found agent: \(agent.name)")
        return agentToDict(agent)
    }

    /// list_agents - 全エージェント一覧を取得
    /// ⚠️ Phase 5で非推奨: list_subordinates を使用
    func listAgents() throws -> [[String: Any]] {
        let agents = try agentRepository.findAll()
        return agents.map { agentToDict($0) }
    }

    // MARK: - Phase 5: Manager-Only Tools

    /// list_subordinates - マネージャーの下位エージェント一覧を取得
    /// 参照: Sources/MCPServer/Authorization/ToolAuthorization.swift
    func listSubordinates(managerId: String) throws -> [[String: Any]] {
        Self.log("[MCP] listSubordinates called for manager: '\(managerId)'")

        // マネージャーの下位エージェント（parentAgentId == managerId）を取得
        let allAgents = try agentRepository.findAll()
        let subordinates = allAgents.filter { $0.parentAgentId?.value == managerId }

        Self.log("[MCP] Found \(subordinates.count) subordinates for manager '\(managerId)'")

        return subordinates.map { agent in
            [
                "id": agent.id.value,
                "name": agent.name,
                "role": agent.role,
                "type": agent.type.rawValue,
                "hierarchy_type": agent.hierarchyType.rawValue,
                "status": agent.status.rawValue
            ]
        }
    }

    /// get_subordinate_profile - 下位エージェントの詳細情報を取得
    /// 参照: Sources/MCPServer/Authorization/ToolAuthorization.swift
    /// 参照: docs/design/AGENT_SKILLS.md
    func getSubordinateProfile(managerId: String, targetAgentId: String) throws -> [String: Any] {
        Self.log("[MCP] getSubordinateProfile called by manager: '\(managerId)' for target: '\(targetAgentId)'")

        let targetId = AgentID(value: targetAgentId)
        guard let agent = try agentRepository.findById(targetId) else {
            throw MCPError.agentNotFound(targetAgentId)
        }

        // 下位エージェントかどうかを検証
        guard agent.parentAgentId?.value == managerId else {
            throw MCPError.notSubordinate(managerId: managerId, targetId: targetAgentId)
        }

        Self.log("[MCP] Found subordinate: \(agent.name)")

        // スキル情報を取得
        let assignedSkills = try agentSkillAssignmentRepository.findByAgentId(targetId)
        Self.log("[MCP] Subordinate has \(assignedSkills.count) assigned skills")

        // 詳細情報（システムプロンプト・スキル含む）を返す
        return [
            "id": agent.id.value,
            "name": agent.name,
            "role": agent.role,
            "type": agent.type.rawValue,
            "hierarchy_type": agent.hierarchyType.rawValue,
            "status": agent.status.rawValue,
            "system_prompt": agent.systemPrompt ?? "",
            "parent_agent_id": agent.parentAgentId?.value ?? NSNull(),
            "ai_type": agent.aiType?.rawValue ?? NSNull(),
            "kick_method": agent.kickMethod.rawValue,
            "max_parallel_tasks": agent.maxParallelTasks,
            "skills": assignedSkills.map { skill in
                [
                    "id": skill.id.value,
                    "name": skill.name,
                    "directory_name": skill.directoryName,
                    "archive_base64": skill.archiveData.base64EncodedString()
                ]
            }
        ]
    }

    /// get_agent_profile (Coordinator用) - エージェントの詳細情報を取得
    /// 参照: docs/design/AGENT_CONTEXT_DIRECTORY.md
    /// 参照: docs/design/AGENT_SKILLS.md
    /// Coordinatorがエージェント起動時にsystem_promptとskillsを取得するために使用
    func getAgentProfileForCoordinator(agentId: String) throws -> [String: Any] {
        Self.log("[MCP] getAgentProfileForCoordinator called for agent: '\(agentId)'")

        let targetId = AgentID(value: agentId)
        guard let agent = try agentRepository.findById(targetId) else {
            throw MCPError.agentNotFound(agentId)
        }

        Self.log("[MCP] Found agent: \(agent.name)")

        // スキル情報を取得
        let assignedSkills = try agentSkillAssignmentRepository.findByAgentId(targetId)
        Self.log("[MCP] Agent has \(assignedSkills.count) assigned skills")

        // 詳細情報（システムプロンプト・スキル含む）を返す
        return [
            "id": agent.id.value,
            "name": agent.name,
            "role": agent.role,
            "type": agent.type.rawValue,
            "hierarchy_type": agent.hierarchyType.rawValue,
            "status": agent.status.rawValue,
            "system_prompt": agent.systemPrompt ?? "",
            "parent_agent_id": agent.parentAgentId?.value ?? NSNull(),
            "ai_type": agent.aiType?.rawValue ?? NSNull(),
            "kick_method": agent.kickMethod.rawValue,
            "max_parallel_tasks": agent.maxParallelTasks,
            "skills": assignedSkills.map { skill in
                [
                    "id": skill.id.value,
                    "name": skill.name,
                    "directory_name": skill.directoryName,
                    "archive_base64": skill.archiveData.base64EncodedString()
                ]
            }
        ]
    }

    /// list_projects - 全プロジェクト一覧を取得
    func listProjects() throws -> [[String: Any]] {
        let projects = try projectRepository.findAll()
        return projects.map { projectToDict($0) }
    }

    /// get_project - プロジェクト詳細を取得
    func getProject(projectId: String) throws -> [String: Any] {
        let id = ProjectID(value: projectId)
        guard let project = try projectRepository.findById(id) else {
            throw MCPError.projectNotFound(projectId)
        }
        return projectToDict(project)
    }

    /// list_active_projects_with_agents - アクティブプロジェクトと割り当てエージェント一覧
    /// 参照: docs/requirements/PROJECTS.md - MCP API
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.3
    /// Runnerがポーリング対象を決定するために使用
    /// - Parameter agentId: オプション。指定された場合、そのエージェントのAgentWorkingDirectoryを参照して
    ///                     プロジェクトごとのworking_directoryを解決（マルチデバイス対応）
    func listActiveProjectsWithAgents(agentId: String? = nil) throws -> [String: Any] {
        // アクティブなプロジェクトのみ取得
        let allProjects = try projectRepository.findAll()
        let activeProjects = allProjects.filter { $0.status == .active }

        var projectsWithAgents: [[String: Any]] = []

        for project in activeProjects {
            // 各プロジェクトに割り当てられたエージェントを取得
            let agents = try projectAgentAssignmentRepository.findAgentsByProject(project.id)
            let agentIdsList = agents.map { $0.id.value }

            // Phase 2.3: working_directoryの解決
            // 優先順位: AgentWorkingDirectory > Project.workingDirectory
            var workingDirectory = project.workingDirectory ?? ""
            if let humanAgentIdStr = agentId {
                let humanAgentId = AgentID(value: humanAgentIdStr)
                if let agentWorkingDir = try agentWorkingDirectoryRepository.findByAgentAndProject(
                    agentId: humanAgentId,
                    projectId: project.id
                ) {
                    workingDirectory = agentWorkingDir.workingDirectory
                }
            }

            let projectEntry: [String: Any] = [
                "project_id": project.id.value,
                "project_name": project.name,
                "working_directory": workingDirectory,
                "agents": agentIdsList
            ]
            projectsWithAgents.append(projectEntry)
        }

        return ["projects": projectsWithAgents]
    }

    /// list_tasks - タスク一覧を取得（フィルタ可能）
    /// ステートレス設計: project_idは不要、全プロジェクトのタスクを返す
    func listTasks(status: String?, assigneeId: String?) throws -> [[String: Any]] {
        var tasks: [Task]

        // まず全タスクを取得（全プロジェクト）
        tasks = try taskRepository.findAllTasks()

        // ステータスでフィルタ
        if let statusString = status,
           let taskStatus = TaskStatus(rawValue: statusString) {
            tasks = tasks.filter { $0.status == taskStatus }
        }

        // アサイニーでフィルタ
        if let assigneeIdString = assigneeId {
            let targetAgentId = AgentID(value: assigneeIdString)
            tasks = tasks.filter { $0.assigneeId == targetAgentId }
        }

        return tasks.map { taskToDict($0) }
    }

    /// Phase 3-2: get_pending_tasks - 作業中タスク取得
    /// 外部Runnerが作業継続のため現在進行中のタスクを取得
    /// Note: working_directoryはコーディネーターが管理するため返さない
    func getPendingTasks(agentId: String) throws -> [String: Any] {
        let useCase = GetPendingTasksUseCase(taskRepository: taskRepository)
        let tasks = try useCase.execute(agentId: AgentID(value: agentId))

        return [
            "success": true,
            "tasks": tasks.map { taskToDict($0) }
        ]
    }

    /// get_task - タスク詳細を取得
    func getTask(taskId: String) throws -> [String: Any] {
        let id = TaskID(value: taskId)
        guard let task = try taskRepository.findById(id) else {
            throw MCPError.taskNotFound(taskId)
        }

        let latestContext = try contextRepository.findLatest(taskId: id)

        var result = taskToDict(task)
        if let ctx = latestContext {
            result["latest_context"] = contextToDict(ctx)
        }

        return result
    }

    /// create_task - 新規タスク作成（サブタスク作成用）
    /// Agent Instanceがメインタスクをサブタスクに分解する際に使用
    func createTask(
        agentId: AgentID,
        projectId: ProjectID,
        title: String,
        description: String,
        priority: String?,
        parentTaskId: String?,
        dependencies: [String]?
    ) throws -> [String: Any] {
        // 優先度のパース
        let taskPriority: TaskPriority
        if let priorityStr = priority, let parsed = TaskPriority(rawValue: priorityStr) {
            taskPriority = parsed
        } else {
            taskPriority = .medium
        }

        // 親タスクIDの検証
        var parentId: TaskID?
        if let parentTaskIdStr = parentTaskId {
            parentId = TaskID(value: parentTaskIdStr)
            guard try taskRepository.findById(parentId!) != nil else {
                throw MCPError.taskNotFound(parentTaskIdStr)
            }
        }

        // 依存タスクIDの検証
        var taskDependencies: [TaskID] = []
        if let deps = dependencies {
            for depId in deps {
                let depTaskId = TaskID(value: depId)
                guard try taskRepository.findById(depTaskId) != nil else {
                    throw MCPError.taskNotFound(depId)
                }
                taskDependencies.append(depTaskId)
            }
        }

        // 作成者のエージェントを取得してhierarchyTypeを確認
        let creatorAgent = try agentRepository.findById(agentId)

        // assigneeId の決定:
        // - Manager: nil（assign_task で明示的に割り当てる必要がある）
        // - Worker: 自分自身（自己作成タスクは自分で実行する）
        // これにより、Workerが作成したサブタスクは自動的に自分にアサインされる
        let assigneeId: AgentID?
        if let agent = creatorAgent, agent.hierarchyType == .worker {
            assigneeId = agentId
            Self.log("[MCP] Worker creating task - auto-assigning to self")
        } else {
            assigneeId = nil
        }

        // 新しいタスクを作成
        // createdByAgentId: タスク作成者を記録（委譲タスク判別用）
        let newTask = Task(
            id: TaskID.generate(),
            projectId: projectId,
            title: title,
            description: description,
            status: .todo,
            priority: taskPriority,
            assigneeId: assigneeId,
            createdByAgentId: agentId,
            dependencies: taskDependencies,
            parentTaskId: parentId
        )

        try taskRepository.save(newTask)

        let depsStr = taskDependencies.map { $0.value }.joined(separator: ", ")
        Self.log("[MCP] Task created: \(newTask.id.value) (parent: \(parentTaskId ?? "none"), dependencies: [\(depsStr)], assignee: \(assigneeId?.value ?? "nil"))")

        // 作成者に応じた instruction を決定
        let instruction: String
        if assigneeId != nil {
            // Worker の場合: タスクは既に自分にアサインされている
            instruction = "サブタスクが作成され、あなたに自動的に割り当てられました。全てのサブタスク作成後、get_next_action を呼び出してください。"
        } else {
            // Manager の場合: assign_task で Worker に割り当てが必要
            instruction = "サブタスクが作成されました。assign_task で適切なワーカーに割り当て、update_task_status で in_progress に変更してください。未割り当てのままのタスクは実行されません。"
        }

        return [
            "success": true,
            "task": [
                "id": newTask.id.value,
                "title": newTask.title,
                "description": newTask.description,
                "status": newTask.status.rawValue,
                "priority": newTask.priority.rawValue,
                "assignee_id": assigneeId?.value as Any,
                "parent_task_id": parentTaskId as Any,
                "dependencies": taskDependencies.map { $0.value }
            ],
            "instruction": instruction
        ]
    }

    /// create_tasks_batch - 複数タスクを依存関係付きで一括作成
    /// ローカル参照ID（local_id）を使ってバッチ内でタスク間の依存関係を指定可能
    /// システムがlocal_idを実際のタスクIDに解決する
    func createTasksBatch(
        agentId: AgentID,
        projectId: ProjectID,
        parentTaskId: String,
        tasks: [[String: Any]]
    ) throws -> [String: Any] {
        Self.log("[MCP] createTasksBatch: agentId=\(agentId.value), projectId=\(projectId.value), parentTaskId=\(parentTaskId), taskCount=\(tasks.count)")

        // 親タスクの検証
        let parentId = TaskID(value: parentTaskId)
        guard try taskRepository.findById(parentId) != nil else {
            throw MCPError.taskNotFound(parentTaskId)
        }

        // 作成者のエージェントを取得してhierarchyTypeを確認
        let creatorAgent = try agentRepository.findById(agentId)
        let isWorker = creatorAgent?.hierarchyType == .worker

        // assigneeIdの決定（Worker の場合は自分自身）
        let assigneeId: AgentID? = isWorker ? agentId : nil

        // Phase 1: 全タスクを作成し、local_id → real_id のマッピングを構築
        var localIdToRealId: [String: TaskID] = [:]
        var createdTasks: [(Task, [String])] = []  // (task, local_dependencies)

        for taskDef in tasks {
            guard let localId = taskDef["local_id"] as? String,
                  let title = taskDef["title"] as? String,
                  let description = taskDef["description"] as? String else {
                throw MCPError.validationError("Each task must have local_id, title, and description")
            }

            // 優先度のパース
            let taskPriority: TaskPriority
            if let priorityStr = taskDef["priority"] as? String,
               let parsed = TaskPriority(rawValue: priorityStr) {
                taskPriority = parsed
            } else {
                taskPriority = .medium
            }

            // ローカル依存関係を保存（後で解決する）
            let localDependencies = taskDef["dependencies"] as? [String] ?? []

            // タスクを作成（依存関係は後で設定）
            let newTask = Task(
                id: TaskID.generate(),
                projectId: projectId,
                title: title,
                description: description,
                status: .todo,
                priority: taskPriority,
                assigneeId: assigneeId,
                createdByAgentId: agentId,
                dependencies: [],  // 後で設定
                parentTaskId: parentId
            )

            localIdToRealId[localId] = newTask.id
            createdTasks.append((newTask, localDependencies))

            Self.log("[MCP] createTasksBatch: Created task local_id=\(localId) → real_id=\(newTask.id.value)")
        }

        // Phase 2: ローカル依存関係を実際のTaskIDに解決して保存
        var savedTasks: [[String: Any]] = []

        for (var task, localDependencies) in createdTasks {
            var resolvedDependencies: [TaskID] = []

            for localDep in localDependencies {
                guard let realId = localIdToRealId[localDep] else {
                    throw MCPError.validationError("Unknown dependency local_id: \(localDep)")
                }
                resolvedDependencies.append(realId)
            }

            // 依存関係を設定
            task.dependencies = resolvedDependencies

            // タスクを保存
            try taskRepository.save(task)

            let depsStr = resolvedDependencies.map { $0.value }.joined(separator: ", ")
            Self.log("[MCP] createTasksBatch: Saved task \(task.id.value) with dependencies: [\(depsStr)]")

            savedTasks.append([
                "id": task.id.value,
                "title": task.title,
                "description": task.description,
                "status": task.status.rawValue,
                "priority": task.priority.rawValue,
                "assignee_id": assigneeId?.value as Any,
                "dependencies": resolvedDependencies.map { $0.value }
            ])
        }

        // 作成者に応じた instruction を決定
        let instruction: String
        if isWorker {
            instruction = "\(tasks.count)個のサブタスクが作成され、あなたに自動的に割り当てられました。get_next_action を呼び出してください。"
        } else {
            instruction = "\(tasks.count)個のサブタスクが作成されました。assign_task で適切なワーカーに割り当ててください。"
        }

        return [
            "success": true,
            "tasks": savedTasks,
            "task_count": savedTasks.count,
            "local_id_to_real_id": localIdToRealId.mapValues { $0.value },
            "instruction": instruction
        ]
    }

    /// assign_task - タスクを指定のエージェントに割り当て
    /// バリデーション:
    /// 1. 呼び出し元がマネージャーであること
    /// 2. 割り当て先が呼び出し元の下位エージェントであること（または割り当て解除）
    func assignTask(taskId: String, assigneeId: String?, callingAgentId: String) throws -> [String: Any] {
        Self.log("[MCP] assignTask: taskId=\(taskId), assigneeId=\(assigneeId ?? "nil"), callingAgentId=\(callingAgentId)")

        // 呼び出し元エージェントを取得
        guard let callingAgent = try agentRepository.findById(AgentID(value: callingAgentId)) else {
            throw MCPError.agentNotFound(callingAgentId)
        }

        // バリデーション1: 呼び出し元がマネージャーであること
        guard callingAgent.hierarchyType == .manager else {
            throw MCPError.permissionDenied("assign_task can only be called by manager agents")
        }

        // タスクを取得
        guard var task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        let previousAssigneeId = task.assigneeId?.value

        // 割り当て解除の場合
        if assigneeId == nil {
            task.assigneeId = nil
            task.updatedAt = Date()
            try taskRepository.save(task)

            Self.log("[MCP] assignTask: unassigned task \(taskId)")
            return [
                "success": true,
                "message": "タスクの割り当てを解除しました",
                "task_id": taskId,
                "previous_assignee_id": previousAssigneeId as Any
            ]
        }

        // 割り当て先エージェントを取得
        guard let assignee = try agentRepository.findById(AgentID(value: assigneeId!)) else {
            throw MCPError.agentNotFound(assigneeId!)
        }

        // バリデーション2: 割り当て先が呼び出し元の下位エージェントであること
        guard assignee.parentAgentId == callingAgent.id else {
            throw MCPError.permissionDenied("Can only assign tasks to subordinate agents (agents with parentAgentId = \(callingAgentId))")
        }

        // バリデーション3: 割り当て先がタスクのプロジェクトに属していること
        let isAssigneeInProject = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: assignee.id,
            projectId: task.projectId
        )
        guard isAssigneeInProject else {
            throw MCPError.permissionDenied("Agent '\(assignee.name)' is not assigned to this project. Only project members can be assigned to tasks.")
        }

        // バリデーション4: 割り当て先がアクティブであること
        guard assignee.status == .active else {
            throw MCPError.permissionDenied("Agent '\(assignee.name)' is not active (status: \(assignee.status.rawValue)). Only active agents can be assigned to tasks.")
        }

        // タスクを更新
        task.assigneeId = AgentID(value: assigneeId!)
        task.updatedAt = Date()
        try taskRepository.save(task)

        Self.log("[MCP] assignTask: assigned task \(taskId) to \(assigneeId!)")
        return [
            "success": true,
            "message": "タスクを \(assignee.name) に割り当てました",
            "task_id": taskId,
            "assignee_id": assigneeId!,
            "assignee_name": assignee.name,
            "previous_assignee_id": previousAssigneeId as Any
        ]
    }

    /// update_task_status - タスクのステータスを更新
    /// UpdateTaskStatusUseCaseに委譲（カスケードブロック等のロジックを統一）
    /// 参照: docs/design/EXECUTION_LOG_DESIGN.md - タスク完了時の実行ログ更新
    /// 参照: docs/plan/GET_MY_TASK_PROGRESS.md - done更新時の指示返却
    func updateTaskStatus(taskId: String, status: String, reason: String?, session: AgentSession) throws -> [String: Any] {
        guard let newStatus = TaskStatus(rawValue: status) else {
            throw MCPError.invalidStatus(status)
        }

        // UseCaseを使用してステータス更新（カスケードブロック含む）
        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepository,
            agentRepository: agentRepository,
            eventRepository: eventRepository
        )

        do {
            let result = try useCase.executeWithResult(
                taskId: TaskID(value: taskId),
                newStatus: newStatus,
                agentId: nil,
                sessionId: nil,
                reason: reason
            )

            logDebug("Task \(taskId) status changed: \(result.previousStatus.rawValue) -> \(result.task.status.rawValue)")

            // タスクが done に遷移した場合、対応する実行ログも完了させる
            // これにより、report_completed を呼ばずに update_task_status で完了した場合も
            // 実行ログが正しく完了状態になる
            if newStatus == .done, let assigneeId = result.task.assigneeId {
                if var executionLog = try executionLogRepository.findLatestByAgentAndTask(
                    agentId: assigneeId,
                    taskId: TaskID(value: taskId)
                ), executionLog.status == .running {
                    let duration = Date().timeIntervalSince(executionLog.startedAt)
                    executionLog.complete(
                        exitCode: 0,
                        durationSeconds: duration,
                        logFilePath: nil,
                        errorMessage: nil
                    )
                    try executionLogRepository.save(executionLog)
                    Self.log("[MCP] ExecutionLog auto-completed via update_task_status: \(executionLog.id.value)")
                }
            }

            var response: [String: Any] = [
                "success": true,
                "task": [
                    "id": result.task.id.value,
                    "title": result.task.title,
                    "previous_status": result.previousStatus.rawValue,
                    "new_status": result.task.status.rawValue
                ]
            ]

            // doneへの更新時に次アクションの指示を返す
            // 参照: docs/plan/GET_MY_TASK_PROGRESS.md
            if newStatus == .done {
                // 同一プロジェクト内で自分に割り当てられた未完了タスクを確認
                let allTasks = try taskRepository.findByAssignee(session.agentId)
                let remainingTasks = allTasks.filter { task in
                    task.projectId == session.projectId &&
                    task.status != .done &&
                    task.status != .cancelled
                }

                if remainingTasks.isEmpty {
                    response["instruction"] = "担当タスクが全て完了しました。report_completed を呼び出してください。"
                } else {
                    response["instruction"] = "get_my_task_progress で残りのタスク状況を確認し、必要な作業を続けてください。"
                }
            }

            return response
        } catch UseCaseError.taskNotFound {
            throw MCPError.taskNotFound(taskId)
        } catch UseCaseError.invalidStatusTransition(let from, let to) {
            throw MCPError.invalidStatusTransition(from: from.rawValue, to: to.rawValue)
        } catch UseCaseError.validationFailed(let message) {
            throw MCPError.validationError(message)
        }
    }

    /// assign_task - タスクをエージェントに割り当て
    func assignTask(taskId: String, assigneeId: String?) throws -> [String: Any] {
        Self.log("[MCP] assignTask called: taskId='\(taskId)', assigneeId='\(assigneeId ?? "nil")'")

        guard var task = try taskRepository.findById(TaskID(value: taskId)) else {
            Self.log("[MCP] Task '\(taskId)' not found")
            throw MCPError.taskNotFound(taskId)
        }

        // Validate assignee exists if provided
        if let assigneeIdStr = assigneeId {
            let targetAgentId = AgentID(value: assigneeIdStr)
            guard try agentRepository.findById(targetAgentId) != nil else {
                let allAgents = try? agentRepository.findAll()
                Self.log("[MCP] assignTask: Agent '\(assigneeIdStr)' not found. Available: \(allAgents?.map { $0.id.value } ?? [])")
                throw MCPError.agentNotFound(assigneeIdStr)
            }

            // Validate agent is assigned to the project
            // 参照: docs/requirements/PROJECTS.md - エージェント割り当て制約
            let isAssigned = try projectAgentAssignmentRepository.isAgentAssignedToProject(
                agentId: targetAgentId,
                projectId: task.projectId
            )
            if !isAssigned {
                Self.log("[MCP] assignTask: Agent '\(assigneeIdStr)' is not assigned to project '\(task.projectId.value)'")
                throw MCPError.agentNotAssignedToProject(agentId: assigneeIdStr, projectId: task.projectId.value)
            }
        }

        let previousAssignee = task.assigneeId
        task.assigneeId = assigneeId.map { AgentID(value: $0) }
        task.updatedAt = Date()

        try taskRepository.save(task)

        // Record event
        let eventType: EventType = assigneeId != nil ? .assigned : .unassigned
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: eventType,
            agentId: nil,
            sessionId: nil,
            previousState: previousAssignee?.value,
            newState: assigneeId
        )
        try eventRepository.save(event)

        return [
            "success": true,
            "task": taskToDict(task)
        ]
    }

    // MARK: - Manager Action Selection
    // 参照: docs/design/MANAGER_STATE_MACHINE_V2.md

    /// select_action - マネージャーが次のアクションを選択
    /// Context に選択結果を保存し、次の get_next_action で対応する状態を返す
    func selectAction(session: AgentSession, action: String, reason: String?) throws -> [String: Any] {
        Self.log("[MCP] selectAction: agent=\(session.agentId.value), action=\(action), reason=\(reason ?? "nil")")

        // 有効なアクションか確認
        let validActions = ["dispatch_task", "adjust", "wait", "complete"]
        guard validActions.contains(action) else {
            throw MCPError.validationError("Invalid action: \(action). Valid actions are: \(validActions.joined(separator: ", "))")
        }

        // 現在のタスクを取得
        guard let currentTask = try taskRepository.findByAssignee(session.agentId)
            .filter({ $0.projectId == session.projectId && $0.status == .inProgress })
            .first else {
            throw MCPError.validationError("No active task found for this manager")
        }

        // wait 選択時のバリデーション: ワーカーが稼働中、または起動待ちであること
        if action == "wait" {
            let subordinates = try agentRepository.findByParent(session.agentId)
                .filter { $0.hierarchyType == .worker && $0.status == .active }
            let hasActiveWorkerSession = try subordinates.contains { worker in
                let sessions = try agentSessionRepository.findByAgentIdAndProjectId(worker.id, projectId: currentTask.projectId)
                return !sessions.isEmpty
            }

            if !hasActiveWorkerSession {
                // ワーカーにタスクが割り当て済みか確認
                let allTasks = try taskRepository.findByProject(currentTask.projectId, status: nil)
                let subTasks = allTasks.filter { $0.parentTaskId == currentTask.id }
                let workerAssignedSubTasks = subTasks.filter { task in
                    guard let assigneeId = task.assigneeId else { return false }
                    return assigneeId != session.agentId && (task.status == .inProgress || task.status == .todo)
                }

                if workerAssignedSubTasks.isEmpty {
                    throw MCPError.validationError(
                        "wait は作業中のワーカーがいる場合のみ選択できます。" +
                        "現在ワーカーに割り当てられたタスクがありません。" +
                        "タスクを派遣するには dispatch_task を選択してください。"
                    )
                }
                // タスク割り当て済みだがワーカー未起動 → wait を許可（起動待ち）
                Self.log("[MCP] selectAction: wait allowed - worker assigned but session not yet active (awaiting spawn)")
            }
        }

        // Context に選択結果を保存
        // workflow:selected_dispatch_task, workflow:selected_adjust, workflow:selected_wait の形式
        let workflowSession = Session(
            id: SessionID.generate(),
            projectId: session.projectId,
            agentId: session.agentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(workflowSession)

        let context = Context(
            id: ContextID.generate(),
            taskId: currentTask.id,
            sessionId: workflowSession.id,
            agentId: session.agentId,
            progress: "workflow:selected_\(action)"
        )
        try contextRepository.save(context)

        Self.log("[MCP] selectAction: Saved context with progress=workflow:selected_\(action)")

        return [
            "success": true,
            "selected_action": action,
            "reason": reason as Any,
            "message": "アクション '\(action)' が選択されました。get_next_action を呼び出して詳細指示を取得してください。"
        ]
    }

    // MARK: - Task Request/Approval
    // 参照: docs/design/TASK_REQUEST_APPROVAL.md

    /// request_task - タスク依頼を作成
    /// 依頼者が担当者の上位（祖先）であれば自動承認、そうでなければ承認待ち
    func requestTask(
        session: AgentSession,
        title: String,
        description: String?,
        assigneeId: String,
        priority: String?,
        parentTaskId: String? = nil
    ) throws -> [String: Any] {
        Self.log("[MCP] requestTask: requester=\(session.agentId.value), assignee=\(assigneeId), title=\(title)")

        // 担当者エージェントを取得
        guard let assignee = try agentRepository.findById(AgentID(value: assigneeId)) else {
            throw MCPError.agentNotFound(assigneeId)
        }

        // 担当者がプロジェクトに割り当てられているか確認
        let isAssigneeInProject = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: assignee.id,
            projectId: session.projectId
        )
        guard isAssigneeInProject else {
            throw MCPError.agentNotAssignedToProject(agentId: assigneeId, projectId: session.projectId.value)
        }

        // 全エージェントを取得（階層判定用）
        let allAgents = try agentRepository.findAll()
        let agentsDict = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })

        // 依頼者（実際にタスクを依頼した人）を特定
        // - タスクセッションの場合: session.agentId（エージェント自身）
        // - チャットセッションの場合: チャットメッセージの送信者（依頼者）
        // UC018-B: 上位者からのチャット依頼は自動承認されるべき
        var actualRequester = session.agentId
        if session.purpose == .chat {
            // チャットセッションの場合、最近のメッセージから依頼者を特定
            let messages = try chatRepository.findMessages(projectId: session.projectId, agentId: session.agentId)
            // 自分宛てのメッセージ（他者からの依頼）を取得
            let incomingMessages = messages.filter({ $0.senderId != session.agentId })
            if let lastIncomingMessage = incomingMessages.last {
                actualRequester = lastIncomingMessage.senderId
                Self.log("[MCP] requestTask: Chat session - actual requester is \(actualRequester.value) (from chat message)")
            }
        }

        // 依頼者が担当者の祖先かどうか判定
        let isAncestor = AgentHierarchy.isAncestorOf(
            ancestor: actualRequester,
            descendant: assignee.id,
            agents: agentsDict
        )

        // 優先度のパース
        let taskPriority: TaskPriority
        if let priorityStr = priority, let parsed = TaskPriority(rawValue: priorityStr) {
            taskPriority = parsed
        } else {
            taskPriority = .medium
        }

        // 承認ステータスの決定
        let approvalStatus: ApprovalStatus = isAncestor ? .approved : .pendingApproval

        // タスク作成
        // createdByAgentId には actualRequester を使用
        // チャットセッションの場合: 依頼者（オーナー等）が作成者となり、isDelegatedTask=true になる
        // これによりサブタスク作成フェーズへ進める
        // 親タスクの存在確認
        if let parentId = parentTaskId {
            guard try taskRepository.findById(TaskID(value: parentId)) != nil else {
                throw MCPError.taskNotFound(parentId)
            }
        }

        var newTask = Task(
            id: TaskID.generate(),
            projectId: session.projectId,
            title: title,
            description: description ?? "",
            status: .backlog,
            priority: taskPriority,
            assigneeId: assignee.id,
            createdByAgentId: actualRequester,
            dependencies: [],
            parentTaskId: parentTaskId.map { TaskID(value: $0) },
            requesterId: actualRequester,
            approvalStatus: approvalStatus
        )

        // 自動承認の場合は承認情報も設定
        if isAncestor {
            newTask.approve(by: session.agentId)
        }

        try taskRepository.save(newTask)

        Self.log("[MCP] requestTask: created task \(newTask.id.value) with approval_status=\(approvalStatus.rawValue)")

        // 承認待ちの場合、承認可能なエージェント（担当者の祖先）を取得
        var approvers: [String] = []
        if approvalStatus == .pendingApproval {
            for agent in allAgents {
                if agent.type == .human && AgentHierarchy.isAncestorOf(ancestor: agent.id, descendant: assignee.id, agents: agentsDict) {
                    approvers.append(agent.id.value)
                }
            }

            // 承認者にシステム通知を送信
            for approverId in approvers {
                let notificationMessage = ChatMessage(
                    id: ChatMessageID(value: "sys_task_\(UUID().uuidString.prefix(8))"),
                    senderId: session.agentId,
                    receiverId: AgentID(value: approverId),
                    content: "【タスク依頼】承認依頼があります。\n\nタスク: \(title)\nタスクID: \(newTask.id.value)\n\nタスクボードから承認または却下してください。",
                    createdAt: Date()
                )
                do {
                    try chatRepository.saveMessageDualWrite(
                        notificationMessage,
                        projectId: session.projectId,
                        senderAgentId: session.agentId,
                        receiverAgentId: AgentID(value: approverId)
                    )
                    Self.log("[MCP] requestTask: Sent approval notification to approver \(approverId)")
                } catch {
                    Self.log("[MCP] requestTask: Failed to send notification to \(approverId): \(error)")
                }
            }
        }

        return [
            "success": true,
            "task_id": newTask.id.value,
            "approval_status": approvalStatus.rawValue,
            "approvers": approvers,
            "message": isAncestor
                ? "タスクが自動承認されました。現在のステータスは backlog です。タスクの実行を開始するには「@@タスク開始: \(newTask.id.value)」をチャットで送信してください。"
                : "タスク依頼が作成されました。承認を待っています。承認後、「@@タスク開始: \(newTask.id.value)」でタスクの実行を開始できます。"
        ]
    }

    /// approve_task_request - タスク依頼を承認
    /// 承認者は担当者の祖先である必要がある
    func approveTaskRequest(
        session: AgentSession,
        taskId: String
    ) throws -> [String: Any] {
        Self.log("[MCP] approveTaskRequest: approver=\(session.agentId.value), taskId=\(taskId)")

        // タスクを取得
        guard var task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        // 承認待ち状態であることを確認
        guard task.approvalStatus == .pendingApproval else {
            throw MCPError.validationError("Task is not pending approval (current status: \(task.approvalStatus.rawValue))")
        }

        // 担当者を取得
        guard let assigneeId = task.assigneeId,
              let assignee = try agentRepository.findById(assigneeId) else {
            throw MCPError.validationError("Task has no assignee")
        }

        // 全エージェントを取得（階層判定用）
        let allAgents = try agentRepository.findAll()
        let agentsDict = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })

        // 承認者が担当者の祖先であることを確認
        let isAncestor = AgentHierarchy.isAncestorOf(
            ancestor: session.agentId,
            descendant: assignee.id,
            agents: agentsDict
        )
        guard isAncestor else {
            throw MCPError.permissionDenied("You are not authorized to approve this task request (must be an ancestor of the assignee)")
        }

        // タスクを承認
        task.approve(by: session.agentId)
        task.updatedAt = Date()
        try taskRepository.save(task)

        Self.log("[MCP] approveTaskRequest: approved task \(taskId)")

        return [
            "success": true,
            "task_id": taskId,
            "status": task.status.rawValue,
            "message": "タスク依頼を承認しました"
        ]
    }

    /// reject_task_request - タスク依頼を却下
    /// 却下者は担当者の祖先である必要がある
    func rejectTaskRequest(
        session: AgentSession,
        taskId: String,
        reason: String?
    ) throws -> [String: Any] {
        Self.log("[MCP] rejectTaskRequest: rejector=\(session.agentId.value), taskId=\(taskId)")

        // タスクを取得
        guard var task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        // 承認待ち状態であることを確認
        guard task.approvalStatus == .pendingApproval else {
            throw MCPError.validationError("Task is not pending approval (current status: \(task.approvalStatus.rawValue))")
        }

        // 担当者を取得
        guard let assigneeId = task.assigneeId,
              let assignee = try agentRepository.findById(assigneeId) else {
            throw MCPError.validationError("Task has no assignee")
        }

        // 全エージェントを取得（階層判定用）
        let allAgents = try agentRepository.findAll()
        let agentsDict = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })

        // 却下者が担当者の祖先であることを確認
        let isAncestor = AgentHierarchy.isAncestorOf(
            ancestor: session.agentId,
            descendant: assignee.id,
            agents: agentsDict
        )
        guard isAncestor else {
            throw MCPError.permissionDenied("You are not authorized to reject this task request (must be an ancestor of the assignee)")
        }

        // タスクを却下
        task.reject(reason: reason)
        task.updatedAt = Date()
        try taskRepository.save(task)

        Self.log("[MCP] rejectTaskRequest: rejected task \(taskId)")

        return [
            "success": true,
            "task_id": taskId,
            "status": "rejected",
            "message": "タスク依頼を却下しました"
        ]
    }

    /// save_context - タスクのコンテキストを保存
    /// ステートレス設計: セッションは不要
    func saveContext(taskId: String, arguments: [String: Any]) throws -> [String: Any] {
        let id = TaskID(value: taskId)
        guard let task = try taskRepository.findById(id) else {
            throw MCPError.taskNotFound(taskId)
        }

        // ステートレス設計: セッションIDとエージェントIDは引数から取得（オプション）
        let sessionIdStr = arguments["session_id"] as? String
        let agentIdStr = arguments["agent_id"] as? String

        let context = Context(
            id: ContextID.generate(),
            taskId: id,
            sessionId: sessionIdStr.map { SessionID(value: $0) } ?? SessionID.generate(),
            agentId: agentIdStr.map { AgentID(value: $0) } ?? AgentID(value: "unknown"),
            progress: arguments["progress"] as? String,
            findings: arguments["findings"] as? String,
            blockers: arguments["blockers"] as? String,
            nextSteps: arguments["next_steps"] as? String
        )

        try contextRepository.save(context)

        // Record event
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .context,
            entityId: context.id.value,
            eventType: .created,
            agentId: agentIdStr.map { AgentID(value: $0) },
            sessionId: sessionIdStr.map { SessionID(value: $0) }
        )
        try eventRepository.save(event)

        return [
            "success": true,
            "context": contextToDict(context)
        ]
    }

    /// get_task_context - タスクのコンテキストを取得
    func getTaskContext(taskId: String, includeHistory: Bool) throws -> [String: Any] {
        let id = TaskID(value: taskId)
        guard try taskRepository.findById(id) != nil else {
            throw MCPError.taskNotFound(taskId)
        }

        if includeHistory {
            let contexts = try contextRepository.findByTask(id)
            return [
                "task_id": taskId,
                "contexts": contexts.map { contextToDict($0) }
            ]
        } else {
            if let context = try contextRepository.findLatest(taskId: id) {
                return [
                    "task_id": taskId,
                    "latest_context": contextToDict(context)
                ]
            } else {
                return [
                    "task_id": taskId,
                    "latest_context": NSNull()
                ]
            }
        }
    }

    /// create_handoff - ハンドオフを作成
    /// ステートレス設計: from_agent_idは必須引数
    func createHandoff(taskId: String, fromAgentId: String, summary: String, arguments: [String: Any]) throws -> [String: Any] {
        let id = TaskID(value: taskId)
        guard let task = try taskRepository.findById(id) else {
            throw MCPError.taskNotFound(taskId)
        }

        let fromAgent = AgentID(value: fromAgentId)
        let toAgentId = (arguments["to_agent_id"] as? String).map { AgentID(value: $0) }

        // Validate from agent exists
        guard try agentRepository.findById(fromAgent) != nil else {
            throw MCPError.agentNotFound(fromAgentId)
        }

        // Validate target agent if specified
        if let targetId = toAgentId {
            guard try agentRepository.findById(targetId) != nil else {
                throw MCPError.agentNotFound(targetId.value)
            }
        }

        let handoff = Handoff(
            id: HandoffID.generate(),
            taskId: id,
            fromAgentId: fromAgent,
            toAgentId: toAgentId,
            summary: summary,
            context: arguments["context"] as? String,
            recommendations: arguments["recommendations"] as? String
        )

        try handoffRepository.save(handoff)

        // Record event
        var metadata: [String: String] = [:]
        if let to = toAgentId {
            metadata["to_agent_id"] = to.value
        }

        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .handoff,
            entityId: handoff.id.value,
            eventType: .created,
            agentId: fromAgent,
            sessionId: nil,
            metadata: metadata.isEmpty ? nil : metadata
        )
        try eventRepository.save(event)

        return [
            "success": true,
            "handoff": handoffToDict(handoff)
        ]
    }

    /// accept_handoff - ハンドオフを受領
    /// ステートレス設計: agent_idは必須引数
    func acceptHandoff(handoffId: String, agentId: String) throws -> [String: Any] {
        guard var handoff = try handoffRepository.findById(HandoffID(value: handoffId)) else {
            throw MCPError.handoffNotFound(handoffId)
        }

        let acceptingAgent = AgentID(value: agentId)

        // Check if already accepted
        guard handoff.acceptedAt == nil else {
            throw MCPError.handoffAlreadyAccepted(handoffId)
        }

        // Check if targeted to specific agent
        if let targetAgentId = handoff.toAgentId {
            guard targetAgentId == acceptingAgent else {
                throw MCPError.handoffNotForYou(handoffId)
            }
        }

        handoff.acceptedAt = Date()
        try handoffRepository.save(handoff)

        // Get task for project ID
        guard let task = try taskRepository.findById(handoff.taskId) else {
            throw MCPError.taskNotFound(handoff.taskId.value)
        }

        // Record event
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .handoff,
            entityId: handoff.id.value,
            eventType: .completed,
            agentId: acceptingAgent,
            sessionId: nil,
            previousState: "pending",
            newState: "accepted"
        )
        try eventRepository.save(event)

        return [
            "success": true,
            "handoff": handoffToDict(handoff)
        ]
    }

    /// get_pending_handoffs - 未処理のハンドオフ一覧を取得
    /// ステートレス設計: agent_idがあればそのエージェント向けのみ、なければ全て
    func getPendingHandoffs(agentId: String?) throws -> [[String: Any]] {
        let handoffs: [Handoff]
        if let agentIdStr = agentId {
            let targetAgentId = AgentID(value: agentIdStr)
            handoffs = try handoffRepository.findPending(agentId: targetAgentId)
        } else {
            handoffs = try handoffRepository.findAllPending()
        }
        return handoffs.map { handoffToDict($0) }
    }


}
