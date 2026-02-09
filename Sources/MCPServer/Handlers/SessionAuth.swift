// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Session Validation & Authentication

extension MCPServer {

    // MARK: Session Validation (Phase 3-4)

    /// セッショントークンを検証し、AgentSessionを返す
    /// 参照: セキュリティ改善 - セッショントークン検証の実装
    /// Phase 4: セッションを検証し、完全なAgentSessionオブジェクトを返す（モデル検証用）
    func validateSession(token: String) throws -> AgentSession {
        guard let session = try agentSessionRepository.findByToken(token) else {
            // findByToken は期限切れセッションを除外するので、
            // トークンが見つからない = 無効または期限切れ
            Self.log("[MCP] Session validation failed: token not found or expired", category: .auth)
            throw MCPError.sessionTokenInvalid
        }

        Self.log("[MCP] Session validated for agent: \(session.agentId.value), project: \(session.projectId.value)", category: .auth)
        return session
    }

    /// セッショントークンを検証し、指定されたエージェントIDとの一致も確認
    func validateSessionWithAgent(token: String, expectedAgentId: String) throws -> AgentID {
        let session = try validateSession(token: token)

        // セッションに紐づくエージェントIDと、リクエストのエージェントIDが一致するか確認
        if session.agentId.value != expectedAgentId {
            Self.log("[MCP] Session agent mismatch: session=\(session.agentId.value), requested=\(expectedAgentId)", category: .auth)
            throw MCPError.sessionAgentMismatch(expected: expectedAgentId, actual: session.agentId.value)
        }

        return session.agentId
    }

    /// タスクへのアクセス権限を検証
    /// エージェントが以下のいずれかの条件を満たす場合にアクセスを許可:
    /// 1. タスクの assigneeId が一致
    /// 2. タスクの parentTaskId を持つ親タスクの assigneeId が一致（サブタスク）
    /// 3. タスクが同じプロジェクトに属する（プロジェクト内のタスク参照）
    func validateTaskAccess(taskId: TaskID, session: AgentSession) throws -> Task {
        guard let task = try taskRepository.findById(taskId) else {
            throw MCPError.taskNotFound(taskId.value)
        }

        // 同じプロジェクトのタスクであることを確認
        guard task.projectId == session.projectId else {
            Self.log("[MCP] Task access denied: task project=\(task.projectId.value), session project=\(session.projectId.value)")
            throw MCPError.taskAccessDenied(taskId.value)
        }

        // 直接の担当者、または親タスクの担当者であればアクセス許可
        if task.assigneeId == session.agentId {
            return task
        }

        // サブタスクの場合、親タスクの担当者かチェック
        if let parentId = task.parentTaskId,
           let parentTask = try taskRepository.findById(parentId),
           parentTask.assigneeId == session.agentId {
            return task
        }

        // 同じプロジェクト内であれば読み取りは許可（書き込みは別途チェック）
        return task
    }

    /// タスクへの書き込み権限を検証（より厳格）
    /// エージェントが担当者または親タスクの担当者である場合のみ許可
    func validateTaskWriteAccess(taskId: TaskID, session: AgentSession) throws -> Task {
        guard let task = try taskRepository.findById(taskId) else {
            throw MCPError.taskNotFound(taskId.value)
        }

        // 同じプロジェクトのタスクであることを確認
        guard task.projectId == session.projectId else {
            Self.log("[MCP] Task write access denied: task project=\(task.projectId.value), session project=\(session.projectId.value)")
            throw MCPError.taskAccessDenied(taskId.value)
        }

        // 直接の担当者であればアクセス許可
        if task.assigneeId == session.agentId {
            return task
        }

        // サブタスクの場合、親タスクの担当者かチェック
        if let parentId = task.parentTaskId,
           let parentTask = try taskRepository.findById(parentId),
           parentTask.assigneeId == session.agentId {
            return task
        }

        Self.log("[MCP] Task write access denied: agent=\(session.agentId.value), task assignee=\(task.assigneeId?.value ?? "nil")")
        throw MCPError.taskAccessDenied(taskId.value)
    }


}

// MARK: - Authentication

extension MCPServer {

    // MARK: Authentication (Phase 4)

    /// エージェント階層を遡って人間エージェントのワーキングディレクトリを取得
    /// 優先順位: 1. 上位の人間エージェントのワーキングディレクトリ 2. プロジェクトデフォルト
    func findHumanAgentWorkingDirectory(
        startAgentId: AgentID,
        projectId: ProjectID,
        fallbackProjectWorkingDir: String?
    ) throws -> String? {
        var currentAgentId: AgentID? = startAgentId
        var visitedIds = Set<String>()  // 循環参照防止

        while let agentId = currentAgentId {
            // 循環参照チェック
            if visitedIds.contains(agentId.value) {
                Self.log("[MCP] Circular reference detected in agent hierarchy at: \(agentId.value)", category: .auth)
                break
            }
            visitedIds.insert(agentId.value)

            // エージェントを取得
            guard let agent = try agentRepository.findById(agentId) else {
                Self.log("[MCP] Agent not found in hierarchy: \(agentId.value)", category: .auth)
                break
            }

            // 人間エージェントかチェック
            if agent.type == .human {
                // 人間エージェントのワーキングディレクトリを確認
                if let agentWorkingDir = try? agentWorkingDirectoryRepository.findByAgentAndProject(
                    agentId: agentId,
                    projectId: projectId
                ) {
                    Self.log("[MCP] Found human agent working directory: \(agentWorkingDir.workingDirectory) for agent: \(agent.name)", category: .auth)
                    return agentWorkingDir.workingDirectory
                }
                Self.log("[MCP] Human agent \(agent.name) has no working directory for this project", category: .auth)
            }

            // 親エージェントに移動
            if let parentId = agent.parentAgentId {
                currentAgentId = parentId
            } else {
                // 親がない場合は終了
                break
            }
        }

        // 見つからない場合はプロジェクトデフォルトにフォールバック
        Self.log("[MCP] No human agent working directory found, using project default: \(fallbackProjectWorkingDir ?? "nil")", category: .auth)
        return fallbackProjectWorkingDir
    }

    /// authenticate - エージェント認証
    /// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md, PHASE4_COORDINATOR_ARCHITECTURE.md
    /// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md - 新アーキテクチャ
    /// Phase 4: project_id 必須、instruction フィールドを追加、二重起動防止
    func authenticate(agentId: String, passkey: String, projectId: String) throws -> [String: Any] {
        Self.log("[MCP] authenticate called for agent: '\(agentId)', project: '\(projectId)'", category: .auth)

        let id = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // Phase 4: プロジェクト存在確認
        guard let project = try projectRepository.findById(projId) else {
            Self.log("[MCP] authenticate failed: Project '\(projectId)' not found", category: .auth)
            // 失敗時も spawn_started_at をクリア（長期ブロック防止）
            try? clearSpawnStarted(agentId: id, projectId: projId)
            return [
                "success": false,
                "error": "Project not found",
                "action": "exit",
                "instruction": "プロジェクトが見つかりません。プロセスを終了してください。"
            ]
        }

        // Phase 4: エージェントがプロジェクトに割り当てられているか確認
        let isAssigned = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: id,
            projectId: projId
        )
        if !isAssigned {
            Self.log("[MCP] authenticate failed: Agent '\(agentId)' not assigned to project '\(projectId)'", category: .auth)
            // 失敗時も spawn_started_at をクリア（長期ブロック防止）
            try? clearSpawnStarted(agentId: id, projectId: projId)
            return [
                "success": false,
                "error": "Agent not assigned to project",
                "action": "exit",
                "instruction": "このプロジェクトに割り当てられていません。プロセスを終了してください。"
            ]
        }

        // Session Spawn Architecture: WorkDetectionService ベースの認証
        // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
        // chat と task セッションは独立して存在可能
        // AuthenticateUseCaseV3 が WorkDetectionService を使用して purpose を判定
        let useCase = AuthenticateUseCaseV3(
            credentialRepository: agentCredentialRepository,
            sessionRepository: agentSessionRepository,
            agentRepository: agentRepository,
            workDetectionService: workDetectionService
        )

        let result = try useCase.execute(agentId: agentId, passkey: passkey, projectId: projectId)

        // 成功でも失敗でも spawn_started_at をクリア（長期ブロック防止）
        // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
        try clearSpawnStarted(agentId: id, projectId: projId)

        if result.success {
            Self.log("[MCP] Authentication successful for agent: \(result.agentName ?? agentId)", category: .auth)

            // エージェント階層を遡って人間エージェントのワーキングディレクトリを取得
            // 優先順位: 上位の人間エージェント固有 > プロジェクトデフォルト
            let effectiveWorkingDir = try findHumanAgentWorkingDirectory(
                startAgentId: id,
                projectId: projId,
                fallbackProjectWorkingDir: project.workingDirectory
            )

            // 作業ディレクトリの指示を構築
            let instruction: String
            if let workingDir = effectiveWorkingDir {
                instruction = """
                    get_next_action を呼び出して次の指示を確認してください。

                    【重要】作業ディレクトリ: \(workingDir)
                    - すべてのファイル操作には絶対パスを使用してください
                    - 例: \(workingDir)/document.txt (正しい)
                    - 例: document.txt (間違い - 相対パスは使用不可)
                    - .aiagent/ ディレクトリ内のファイルを変更しないでください

                    【重要】セッション終了時
                    - プロセスを終了する前に必ず `logout` ツールを呼び出してください
                    - これによりセッションが正しくクリーンアップされます
                    """
            } else {
                instruction = """
                    get_next_action を呼び出して次の指示を確認してください。

                    【重要】セッション終了時
                    - プロセスを終了する前に必ず `logout` ツールを呼び出してください
                    - これによりセッションが正しくクリーンアップされます
                    """
            }

            var response: [String: Any] = [
                "success": true,
                "session_token": result.sessionToken ?? "",
                "expires_in": result.expiresIn ?? 0,
                "agent_name": result.agentName ?? "",
                "instruction": instruction
            ]

            // working_directory を明示的に追加（エージェントが参照できるように）
            if let workingDir = effectiveWorkingDir {
                response["working_directory"] = workingDir
            }

            // system_prompt があれば追加（エージェントの役割を定義）
            // 参照: docs/plan/MULTI_AGENT_USE_CASES.md
            if let systemPrompt = result.systemPrompt {
                response["system_prompt"] = systemPrompt
            }
            return response
        } else {
            Self.log("[MCP] Authentication failed for agent: \(agentId) - \(result.error ?? "Unknown error")", category: .auth)
            return [
                "success": false,
                "error": result.error ?? "Authentication failed",
                "action": "exit",
                "instruction": "認証に失敗しました。現在あなたに割り当てられた作業はありません。プロセスを終了してください。"
            ]
        }
    }


}
