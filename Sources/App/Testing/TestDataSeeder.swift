// Sources/App/Testing/TestDataSeeder.swift
// UIテスト用のテストデータシーダー

#if DEBUG

import Foundation
import Domain
import Infrastructure

// MARK: - Test Data Seeder

/// UIテスト用のテストデータを生成するシーダー
final class TestDataSeeder {

    let projectRepository: ProjectRepository
    let agentRepository: AgentRepository
    let taskRepository: TaskRepository
    let templateRepository: WorkflowTemplateRepository?
    let templateTaskRepository: TemplateTaskRepository?
    let internalAuditRepository: InternalAuditRepository?
    let auditRuleRepository: AuditRuleRepository?
    let credentialRepository: AgentCredentialRepository?
    let projectAgentAssignmentRepository: ProjectAgentAssignmentRepository?
    let appSettingsRepository: AppSettingsRepository?

    init(
        projectRepository: ProjectRepository,
        agentRepository: AgentRepository,
        taskRepository: TaskRepository,
        templateRepository: WorkflowTemplateRepository? = nil,
        templateTaskRepository: TemplateTaskRepository? = nil,
        internalAuditRepository: InternalAuditRepository? = nil,
        auditRuleRepository: AuditRuleRepository? = nil,
        credentialRepository: AgentCredentialRepository? = nil,
        projectAgentAssignmentRepository: ProjectAgentAssignmentRepository? = nil,
        appSettingsRepository: AppSettingsRepository? = nil
    ) {
        self.projectRepository = projectRepository
        self.agentRepository = agentRepository
        self.taskRepository = taskRepository
        self.templateRepository = templateRepository
        self.templateTaskRepository = templateTaskRepository
        self.internalAuditRepository = internalAuditRepository
        self.auditRuleRepository = auditRuleRepository
        self.credentialRepository = credentialRepository
        self.projectAgentAssignmentRepository = projectAgentAssignmentRepository
        self.appSettingsRepository = appSettingsRepository
    }

    /// 基本的なテストデータを生成（プロジェクト、エージェント、タスク）
    func seedBasicData() async throws {
        // 作業ディレクトリを作成（存在しない場合）
        let workingDir = "/tmp/basic_test"
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: workingDir) {
            try fileManager.createDirectory(atPath: workingDir, withIntermediateDirectories: true)
        }

        // プロジェクト作成（workingDirectory設定済み）
        let project = Project(
            id: .generate(),
            name: "テストプロジェクト",
            description: "UIテスト用のサンプルプロジェクト",
            status: .active,
            workingDirectory: workingDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(project)

        // エージェント作成（Human - Manager）
        // 要件: エージェントはプロジェクト非依存のトップレベルエンティティ
        let ownerAgent = Agent(
            id: .generate(),
            name: "owner",
            role: "プロジェクトオーナー",
            type: .human,
            roleType: .manager,
            capabilities: [],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(ownerAgent)

        // エージェント作成（AI - Developer、並列数1）
        // maxParallelTasks: 1 でリソースブロックテスト用
        let devAgent = Agent(
            id: .generate(),
            name: "backend-dev",
            role: "バックエンド開発",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,  // 並列数1でテスト用
            capabilities: ["Swift", "Python", "API設計"],
            systemPrompt: "バックエンド開発を担当するAIエージェントです",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(devAgent)

        // 依存関係テスト用: まず先行タスク（未完了）を作成
        // 注意: backlogステータスにして、todoカラムのスクロール問題を回避
        // UIテスト用に固定IDを使用
        let prerequisiteTaskId = TaskID(value: "uitest_prerequisite_task")
        let prerequisiteTask = Task(
            id: prerequisiteTaskId,
            projectId: project.id,
            title: "先行タスク",
            description: "この先行タスクが完了しないと次のタスクを開始できません",
            status: .backlog,  // backlogで未完了（doneではないので依存タスクはブロックされる）
            priority: .high,
            assigneeId: nil,
            dependencies: [],
            estimatedMinutes: nil,
            actualMinutes: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
        try await taskRepository.save(prerequisiteTask)

        // 依存関係テスト用: 先行タスクに依存するタスク
        // UIテスト用に固定IDを使用
        let dependentTaskId = TaskID(value: "uitest_dependent_task")
        let dependentTask = Task(
            id: dependentTaskId,
            projectId: project.id,
            title: "依存タスク",
            description: "先行タスク完了後に開始可能（依存関係テスト用）",
            status: .todo,
            priority: .medium,
            assigneeId: devAgent.id,
            dependencies: [prerequisiteTaskId],  // 先行タスクに依存
            estimatedMinutes: nil,
            actualMinutes: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
        try await taskRepository.save(dependentTask)

        // 各ステータスのタスクを作成
        // 要件: TaskStatusは backlog, todo, in_progress, blocked, done, cancelled のみ
        // 注意: todoカラムには依存タスク・追加開発タスクがあるので、
        //       他のtodoタスクは最小限にしてスクロール問題を回避
        let taskStatuses: [(TaskStatus, String, String, TaskPriority)] = [
            (.backlog, "UI設計", "画面レイアウトの設計", .low),
            // todoには依存テスト用タスクと追加開発タスクのみ
            (.inProgress, "API実装", "REST APIエンドポイントの実装", .high),
            (.done, "要件定義", "プロジェクト要件の定義完了", .high),
            (.blocked, "API統合", "外部APIとの統合（認証待ち）", .urgent),
        ]

        for (status, title, description, priority) in taskStatuses {
            let task = Task(
                id: .generate(),
                projectId: project.id,
                title: title,
                description: description,
                status: status,
                priority: priority,
                assigneeId: status == .inProgress ? devAgent.id : nil,
                dependencies: [],
                estimatedMinutes: nil,
                actualMinutes: nil,
                createdAt: Date(),
                updatedAt: Date(),
                completedAt: status == .done ? Date() : nil
            )
            try await taskRepository.save(task)
        }

        // リソースブロックテスト用: devAgentに追加のtodoタスクをアサイン
        // devAgentは既にAPI実装(inProgress)を持っており、maxParallelTasks=1
        // UIテスト用に固定IDを使用
        let resourceTestTaskId = TaskID(value: "uitest_resource_task")
        let additionalTaskForResourceTest = Task(
            id: resourceTestTaskId,
            projectId: project.id,
            title: "追加開発タスク",
            description: "リソースブロックテスト用（並列数上限確認）",
            status: .todo,  // todoから直接in_progressに遷移を試みる
            priority: .medium,
            assigneeId: devAgent.id,  // devAgentにアサイン
            dependencies: [],
            estimatedMinutes: nil,
            actualMinutes: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
        try await taskRepository.save(additionalTaskForResourceTest)

        // プロジェクトにエージェントを割り当て（Chat機能テスト用）
        if let assignmentRepo = projectAgentAssignmentRepository {
            _ = try assignmentRepo.assign(projectId: project.id, agentId: devAgent.id)
            _ = try assignmentRepo.assign(projectId: project.id, agentId: ownerAgent.id)
        }
    }

    /// 空のプロジェクト状態をシード（プロジェクトなし）
    func seedEmptyState() async throws {
        // 何もしない - 空の状態
    }
}

#endif
