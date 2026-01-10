// Sources/App/Testing/Scenarios/OtherSeeders.swift
// その他のシナリオ用シーダー（MultiProject, NoWD, InternalAudit, WorkflowTemplate）

#if DEBUG

import Foundation
import Domain
import Infrastructure

extension TestDataSeeder {

    /// 複数プロジェクトをシード
    func seedMultipleProjects() async throws {
        let projectNames = ["ECサイト開発", "モバイルアプリ", "管理システム"]

        for name in projectNames {
            let project = Project(
                id: .generate(),
                name: name,
                description: "\(name)のプロジェクト",
                status: .active,
                createdAt: Date(),
                updatedAt: Date()
            )
            try await projectRepository.save(project)

            // 各プロジェクトに基本的なエージェントを追加
            // 要件: エージェントはプロジェクト非依存
            let agent = Agent(
                id: .generate(),
                name: "developer-\(name)",
                role: "開発者",
                type: .ai,
                roleType: .developer,
                capabilities: [],
                systemPrompt: nil,
                status: .active,
                createdAt: Date(),
                updatedAt: Date()
            )
            try await agentRepository.save(agent)

            // 基本的なタスクを追加
            let task = Task(
                id: .generate(),
                projectId: project.id,
                title: "初期タスク",
                description: "プロジェクトの初期タスク",
                status: .backlog,
                priority: .medium
            )
            try await taskRepository.save(task)
        }
    }

    /// NoWDシナリオ: workingDirectory未設定プロジェクトのみをシード
    /// キック時にエラーになることをテストするための専用シナリオ
    func seedNoWDData() async throws {
        // workingDirectory未設定のプロジェクト（唯一のプロジェクト）
        let noWDProject = Project(
            id: ProjectID(value: "uitest_no_wd_project"),
            name: "作業ディレクトリなしPJ",
            description: "作業ディレクトリ未設定のプロジェクト（エラーテスト用）",
            status: .active,
            workingDirectory: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(noWDProject)

        // claude-code-agent（kickMethod=cli設定済み）
        let claudeAgent = Agent(
            id: .generate(),
            name: "claude-code-agent",
            role: "Claude Code CLIエージェント",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 3,
            capabilities: ["TypeScript", "Python", "Swift"],
            systemPrompt: "Claude Codeを使用して開発タスクを実行するエージェントです",
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(claudeAgent)

        // workingDirectory未設定エラーテスト用タスク
        // claude-code-agentにアサインされているが、プロジェクトに作業ディレクトリがないためキック時にエラーになる
        let noWDKickTask = Task(
            id: TaskID(value: "uitest_no_wd_kick_task"),
            projectId: noWDProject.id,
            title: "作業ディレクトリなしキックタスク",
            description: "作業ディレクトリ未設定エラーのテスト用",
            status: .backlog,
            priority: .high,
            assigneeId: claudeAgent.id,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(noWDKickTask)
    }

    /// Internal Audit機能テスト用のデータをシード
    /// - Internal Audit + Audit Rule
    /// - エージェント（タスク割り当て用）
    func seedInternalAuditData() async throws {
        guard let internalAuditRepository = internalAuditRepository,
              let auditRuleRepository = auditRuleRepository else {
            print("⚠️ UITest: Internal Audit repositories not available")
            return
        }

        // エージェント作成（Audit Rule用）
        let qaAgent = Agent(
            id: AgentID(value: "uitest_qa_agent"),
            name: "qa-agent",
            role: "QA Engineer",
            type: .ai,
            roleType: .developer,
            capabilities: ["Testing", "Quality Assurance"],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(qaAgent)

        let reviewerAgent = Agent(
            id: AgentID(value: "uitest_reviewer_agent"),
            name: "reviewer-agent",
            role: "Code Reviewer",
            type: .ai,
            roleType: .developer,
            capabilities: ["Code Review"],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(reviewerAgent)

        // Internal Audit作成
        let auditId = InternalAuditID(value: "uitest_internal_audit")
        let audit = InternalAudit(
            id: auditId,
            name: "Test QA Audit",
            description: "Quality assurance audit for testing purposes",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try internalAuditRepository.save(audit)

        // Audit Rule作成（auditTasksをインラインで定義）
        let ruleId = AuditRuleID(value: "uitest_audit_rule")
        let rule = AuditRule(
            id: ruleId,
            auditId: auditId,
            name: "Task Completion Check",
            triggerType: .taskCompleted,
            triggerConfig: nil,
            auditTasks: [
                AuditTask(
                    order: 1,
                    title: "Run Unit Tests",
                    description: "Execute all unit tests",
                    assigneeId: qaAgent.id,
                    priority: .high,
                    dependsOnOrders: []
                ),
                AuditTask(
                    order: 2,
                    title: "Code Review",
                    description: "Review code changes",
                    assigneeId: reviewerAgent.id,
                    priority: .medium,
                    dependsOnOrders: [1]
                )
            ],
            isEnabled: true
        )
        try auditRuleRepository.save(rule)

        // トリガーテスト用プロジェクト作成
        let triggerTestProject = Project(
            id: ProjectID(value: "uitest_trigger_project"),
            name: "トリガーテストPJ",
            description: "Audit Ruleトリガーのテスト用プロジェクト",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(triggerTestProject)

        // WorkflowTemplate作成（AuditRule作成時のテンプレートインポート用）
        if let templateRepository = templateRepository,
           let templateTaskRepository = templateTaskRepository {
            let qaTemplateId = WorkflowTemplateID(value: "uitest_qa_template")
            let qaTemplate = WorkflowTemplate(
                id: qaTemplateId,
                projectId: triggerTestProject.id,
                name: "QA Workflow Template",
                description: "品質保証用ワークフローテンプレート",
                variables: [],
                status: .active,
                createdAt: Date(),
                updatedAt: Date()
            )
            try templateRepository.save(qaTemplate)

            // テンプレートタスク作成
            let task1 = TemplateTask(
                id: TemplateTaskID(value: "uitest_qa_template_task_1"),
                templateId: qaTemplateId,
                title: "Quality Check",
                description: "品質チェックを実行",
                order: 1,
                dependsOnOrders: [],
                defaultAssigneeRole: .developer,
                defaultPriority: .high,
                estimatedMinutes: 60
            )
            try templateTaskRepository.save(task1)

            let task2 = TemplateTask(
                id: TemplateTaskID(value: "uitest_qa_template_task_2"),
                templateId: qaTemplateId,
                title: "Approval",
                description: "承認プロセス",
                order: 2,
                dependsOnOrders: [1],
                defaultAssigneeRole: .manager,
                defaultPriority: .medium,
                estimatedMinutes: 30
            )
            try templateTaskRepository.save(task2)

            print("✅ UITest: QA Workflow Template created with 2 tasks")
        }

        // トリガーテスト用タスク（inProgress状態 → doneに変更でトリガー発火）
        let triggerTestTask = Task(
            id: TaskID(value: "uitest_trigger_task"),
            projectId: triggerTestProject.id,
            title: "トリガーテストタスク",
            description: "このタスクを完了するとAudit Ruleがトリガーされ、QA Workflowタスクが自動生成されます",
            status: .inProgress,  // 完了可能な状態
            priority: .high,
            assigneeId: qaAgent.id,
            dependencies: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(triggerTestTask)

        // 追加：完了済みタスク（トリガー発火後の確認用比較対象）
        let completedTask = Task(
            id: TaskID(value: "uitest_completed_task"),
            projectId: triggerTestProject.id,
            title: "完了済みタスク",
            description: "既に完了したタスク",
            status: .done,
            priority: .medium,
            assigneeId: nil,
            dependencies: [],
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: Date()
        )
        try await taskRepository.save(completedTask)

        // ロックテスト用タスク（既にロック済み）
        let lockedTask = Task(
            id: TaskID(value: "uitest_locked_task"),
            projectId: triggerTestProject.id,
            title: "ロック済みタスク",
            description: "監査によりロックされたタスク - ステータス変更不可",
            status: .inProgress,
            priority: .high,
            assigneeId: qaAgent.id,
            dependencies: [],
            createdAt: Date(),
            updatedAt: Date(),
            isLocked: true,
            lockedByAuditId: auditId,
            lockedAt: Date()
        )
        try await taskRepository.save(lockedTask)

        print("✅ UITest: Internal Audit test data seeded successfully")
    }

    /// WorkflowTemplate機能テスト用のデータをシード
    func seedWorkflowTemplateData() async throws {
        NSLog("🔧 UITest: seedWorkflowTemplateData() - START")

        // Debug: Write to temp file to confirm seeder runs
        let debugPath = "/tmp/uitest_workflow_debug.txt"
        try? "seedWorkflowTemplateData() started at \(Date())\n".write(toFile: debugPath, atomically: true, encoding: .utf8)

        // プロジェクト作成（テンプレートが所属するプロジェクト）
        NSLog("🔧 UITest: Creating project...")
        let project = Project(
            id: ProjectID(value: "uitest_template_project"),
            name: "テンプレートテストPJ",
            description: "ワークフローテンプレート機能のテスト用プロジェクト",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try projectRepository.save(project)
        NSLog("🔧 UITest: Project saved successfully - id=\(project.id.value)")

        // Debug: verify project was saved
        let savedProjects = try projectRepository.findAll()
        let debugContent = """
        Project saved at \(Date())
        id: \(project.id.value)
        Projects in DB: \(savedProjects.count)
        Project names: \(savedProjects.map { $0.name })
        """
        try? debugContent.appendToFile("/tmp/uitest_workflow_debug.txt")

        NSLog("🔧 UITest: templateRepository=\(String(describing: templateRepository != nil)), templateTaskRepository=\(String(describing: templateTaskRepository != nil))")
        try? "templateRepository=\(templateRepository != nil), templateTaskRepository=\(templateTaskRepository != nil)".appendToFile("/tmp/uitest_workflow_debug.txt")

        guard let templateRepository = templateRepository,
              let templateTaskRepository = templateTaskRepository else {
            NSLog("⚠️ UITest: Workflow Template repositories not available - but project created")
            try? "⚠️ GUARD FAILED: repositories are nil - returning early".appendToFile("/tmp/uitest_workflow_debug.txt")
            return
        }

        try? "✅ Repositories available, creating template...".appendToFile("/tmp/uitest_workflow_debug.txt")

        // エージェント作成（テンプレートタスクのデフォルト担当用）
        NSLog("🔧 UITest: Creating agents...")
        let devAgent = Agent(
            id: AgentID(value: "uitest_template_dev_agent"),
            name: "template-dev",
            role: "開発者",
            type: .ai,
            roleType: .developer,
            capabilities: ["Development"],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try agentRepository.save(devAgent)

        let qaAgent = Agent(
            id: AgentID(value: "uitest_template_qa_agent"),
            name: "template-qa",
            role: "QA担当",
            type: .ai,
            roleType: .developer,
            capabilities: ["Testing", "QA"],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try agentRepository.save(qaAgent)
        NSLog("🔧 UITest: Agents created")

        // ワークフローテンプレート作成（変数付き）
        let templateId = WorkflowTemplateID(value: "uitest_workflow_template")
        let template = WorkflowTemplate(
            id: templateId,
            projectId: project.id,
            name: "Feature Development",
            description: "機能開発用のワークフローテンプレート",
            variables: ["feature_name", "sprint_number"],
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try templateRepository.save(template)
        try? "✅ Template 'Feature Development' saved with id=\(templateId.value)".appendToFile("/tmp/uitest_workflow_debug.txt")
        NSLog("🔧 UITest: Template saved - id=\(templateId.value)")

        // テンプレートタスク作成
        let task1 = TemplateTask(
            id: TemplateTaskID(value: "uitest_template_task_1"),
            templateId: templateId,
            title: "{{feature_name}} 設計",
            description: "Sprint {{sprint_number}}: 機能の設計を行う",
            order: 1,
            dependsOnOrders: [],
            defaultAssigneeRole: .developer,
            defaultPriority: .high,
            estimatedMinutes: 120
        )
        try templateTaskRepository.save(task1)

        let task2 = TemplateTask(
            id: TemplateTaskID(value: "uitest_template_task_2"),
            templateId: templateId,
            title: "{{feature_name}} 実装",
            description: "Sprint {{sprint_number}}: 機能の実装を行う",
            order: 2,
            dependsOnOrders: [1],  // 設計に依存
            defaultAssigneeRole: .developer,
            defaultPriority: .high,
            estimatedMinutes: 240
        )
        try templateTaskRepository.save(task2)

        let task3 = TemplateTask(
            id: TemplateTaskID(value: "uitest_template_task_3"),
            templateId: templateId,
            title: "{{feature_name}} テスト",
            description: "Sprint {{sprint_number}}: 機能のテストを行う",
            order: 3,
            dependsOnOrders: [2],  // 実装に依存
            defaultAssigneeRole: .developer,
            defaultPriority: .medium,
            estimatedMinutes: 180
        )
        try templateTaskRepository.save(task3)

        // アーカイブ済みテンプレート（表示確認用）
        let archivedTemplateId = WorkflowTemplateID(value: "uitest_archived_template")
        let archivedTemplate = WorkflowTemplate(
            id: archivedTemplateId,
            projectId: project.id,
            name: "Archived Template",
            description: "アーカイブ済みのテンプレート",
            variables: [],
            status: .archived,
            createdAt: Date(),
            updatedAt: Date()
        )
        try templateRepository.save(archivedTemplate)

        NSLog("✅ UITest: Workflow Template test data seeded successfully")
    }
}
#endif
