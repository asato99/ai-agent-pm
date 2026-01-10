// Sources/App/Testing/Scenarios/UC003Seeder.swift
// UC003: AIタイプ切り替え検証用シーダー

#if DEBUG

import Foundation
import Domain
import Infrastructure

extension TestDataSeeder {

    /// UC003用のテストデータを生成（AIタイプ切り替え検証）
    /// - 1つのプロジェクト
    /// - 2つのエージェント（Claude標準、カスタムkickCommand）
    /// - 各エージェントに1タスク
    ///
    /// 検証内容:
    /// - aiTypeがget_agent_action APIで正しく返されること
    /// - kickCommandがaiTypeより優先されること
    func seedUC003Data() async throws {
        print("=== UC003 Test Data Configuration ===")
        print("Design: 1 project + 2 agents (different aiType/kickCommand)")

        guard let projectAgentAssignmentRepository = projectAgentAssignmentRepository else {
            print("⚠️ UC003: projectAgentAssignmentRepository not available")
            return
        }

        // 作業ディレクトリを作成
        let fileManager = FileManager.default
        let workingDir = "/tmp/uc003"
        if !fileManager.fileExists(atPath: workingDir) {
            try fileManager.createDirectory(atPath: workingDir, withIntermediateDirectories: true)
        }

        // UC003用プロジェクト
        let projectId = ProjectID(value: "prj_uc003")
        let project = Project(
            id: projectId,
            name: "UC003 AIType Test",
            description: "AIタイプ切り替え検証用プロジェクト",
            status: .active,
            workingDirectory: workingDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(project)
        print("✅ UC003: Project created - \(project.name)")

        // UC003用エージェント1: Claude Sonnet 4.5（kickCommand=nil）
        let sonnetAgentId = AgentID(value: "agt_uc003_sonnet")
        let sonnetAgent = Agent(
            id: sonnetAgentId,
            name: "UC003 Sonnet Agent",
            role: "Claude Sonnet 4.5エージェント",
            type: .ai,
            aiType: .claudeSonnet4_5,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["TypeScript", "Python"],
            systemPrompt: "あなたは開発タスクを実行するAIエージェントです。指示されたファイルを作成してください。",
            kickMethod: .cli,
            kickCommand: nil,  // kickCommand未設定 → aiTypeが使われる
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(sonnetAgent)
        print("✅ UC003: Sonnet agent created - \(sonnetAgent.name) (aiType=claudeSonnet4_5, kickCommand=nil)")

        // UC003用エージェント2: Claude Opus 4（カスタムkickCommand）
        let opusAgentId = AgentID(value: "agt_uc003_opus")
        let opusAgent = Agent(
            id: opusAgentId,
            name: "UC003 Opus Agent",
            role: "Claude Opus 4エージェント",
            type: .ai,
            aiType: .claudeOpus4,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["TypeScript", "Python"],
            systemPrompt: "あなたは開発タスクを実行するAIエージェントです。指示されたファイルを作成してください。",
            kickMethod: .cli,
            kickCommand: "claude --model opus --dangerously-skip-permissions --max-turns 80",  // kickCommandが優先される
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(opusAgent)
        print("✅ UC003: Opus agent created - \(opusAgent.name) (aiType=claudeOpus4, kickCommand includes --max-turns 50)")

        // Runner認証用クレデンシャル
        if let credentialRepository = credentialRepository {
            let sonnetCredential = AgentCredential(
                agentId: sonnetAgentId,
                rawPasskey: "test_passkey_uc003_sonnet"
            )
            try credentialRepository.save(sonnetCredential)
            print("✅ UC003: Credential created for \(sonnetAgentId.value)")

            let opusCredential = AgentCredential(
                agentId: opusAgentId,
                rawPasskey: "test_passkey_uc003_opus"
            )
            try credentialRepository.save(opusCredential)
            print("✅ UC003: Credential created for \(opusAgentId.value)")
        }

        // エージェントをプロジェクトに割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: sonnetAgentId)
        print("✅ UC003: Sonnet agent assigned to project")
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: opusAgentId)
        print("✅ UC003: Opus agent assigned to project")

        // Sonnetエージェント用タスク
        let sonnetTask = Task(
            id: TaskID(value: "tsk_uc003_sonnet"),
            projectId: projectId,
            title: "Sonnet Task",
            description: """
                【タスク指示】
                OUTPUT_1.md というファイルを作成してください。
                内容は「タスク完了」という文字列を含めてください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: sonnetAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(sonnetTask)
        print("✅ UC003: Sonnet task created")

        // Opusエージェント用タスク
        let opusTask = Task(
            id: TaskID(value: "tsk_uc003_opus"),
            projectId: projectId,
            title: "Opus Task",
            description: """
                【タスク指示】
                OUTPUT_2.md というファイルを作成してください。
                内容は「タスク完了」という文字列を含めてください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: opusAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(opusTask)
        print("✅ UC003: Opus task created")

        print("✅ UC003: All test data seeded successfully (1 project, 2 agents, 2 tasks)")
    }
}
#endif
