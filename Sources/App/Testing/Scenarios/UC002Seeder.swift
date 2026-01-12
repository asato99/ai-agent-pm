// Sources/App/Testing/Scenarios/UC002Seeder.swift
// UC002: マルチエージェント協調テスト用シーダー

#if DEBUG

import Foundation
import Domain
import Infrastructure

extension TestDataSeeder {

    /// UC002用のテストデータを生成（マルチエージェント協調テスト用）
    /// - 2つのエージェント（詳細ライター、簡潔ライター）
    /// - 両方ともclaude、異なるsystem_promptで出力差異を検証
    /// - 出力ファイル: PROJECT_SUMMARY.md
    func seedUC002Data() async throws {
        // デバッグ出力
        print("=== UC002 Test Data Configuration ===")
        print("Design: Single project + 2 identical tasks with different agents")

        // Debug: Log to file for investigation
        let debugPath = "/tmp/uc002_seed_debug.txt"
        try? "UC002 seeding started at \(Date())\n".write(toFile: debugPath, atomically: true, encoding: .utf8)

        // UC002用プロジェクト（1つのみ）
        let projectId = ProjectID(value: "prj_uc002_test")
        let project = Project(
            id: projectId,
            name: "UC002マルチエージェントテストPJ",
            description: "マルチエージェント協調テスト - 同一タスク指示で異なるsystem_promptによる出力差異を検証",
            status: .active,
            workingDirectory: "/tmp/uc002_test",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(project)
        try? "Project saved: \(project.id.value)\n".appendToFile("/tmp/uc002_seed_debug.txt")
        print("✅ UC002: Project created - \(project.name)")

        // 詳細ライターエージェント（Claude / 詳細system_prompt）
        let detailedAgentId = AgentID(value: "agt_detailed_writer")
        let detailedAgent = Agent(
            id: detailedAgentId,
            name: "詳細ライター",
            role: "詳細なドキュメント作成",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["Documentation", "Writing"],
            systemPrompt: "詳細で包括的なドキュメントを作成してください。背景、目的、使用例を必ず含めてください。",
            kickMethod: .cli,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(detailedAgent)

        // 簡潔ライターエージェント（Claude / 簡潔system_prompt）
        let conciseAgentId = AgentID(value: "agt_concise_writer")
        let conciseAgent = Agent(
            id: conciseAgentId,
            name: "簡潔ライター",
            role: "簡潔なドキュメント作成",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["Documentation", "Writing"],
            systemPrompt: "簡潔に要点のみ記載してください。箇条書きで3項目以内にまとめてください。",
            kickMethod: .cli,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(conciseAgent)
        try? "Agents saved: \(detailedAgentId.value), \(conciseAgentId.value)\n".appendToFile("/tmp/uc002_seed_debug.txt")
        print("✅ UC002: Agents created - 詳細ライター, 簡潔ライター")

        // Runner認証用クレデンシャル
        if let credentialRepository = credentialRepository {
            let detailedCredential = AgentCredential(
                agentId: detailedAgentId,
                rawPasskey: "test_passkey_detailed"
            )
            try credentialRepository.save(detailedCredential)

            let conciseCredential = AgentCredential(
                agentId: conciseAgentId,
                rawPasskey: "test_passkey_concise"
            )
            try credentialRepository.save(conciseCredential)
            print("✅ UC002: Runner credentials created")
        }

        // エージェントをプロジェクトに割り当て（Coordinator用）
        if let projectAgentAssignmentRepository = projectAgentAssignmentRepository {
            _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: detailedAgentId)
            _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: conciseAgentId)
            print("✅ UC002: Agents assigned to project")
        }

        // タスク1: 詳細ライター用（backlog状態 → UIテストでin_progressに変更）
        let detailedTaskDescription = """
            OUTPUT_A.md にプロジェクトサマリードキュメントを作成してください。

            【対象トピック】
            - プロジェクトの目的
            - 主要な機能
            - 今後の展望
            """
        let detailedTask = Task(
            id: TaskID(value: "tsk_uc002_detailed"),
            projectId: projectId,
            title: "プロジェクトサマリー作成",
            description: detailedTaskDescription,
            status: .backlog,
            priority: .high,
            assigneeId: detailedAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(detailedTask)
        print("✅ UC002: Task 1 created - assigned to 詳細ライター (OUTPUT_A.md)")

        // タスク2: 簡潔ライター用（backlog状態 → UIテストでin_progressに変更）
        let conciseTaskDescription = """
            OUTPUT_B.md にプロジェクトサマリードキュメントを作成してください。

            【対象トピック】
            - プロジェクトの目的
            - 主要な機能
            - 今後の展望
            """
        let conciseTask = Task(
            id: TaskID(value: "tsk_uc002_concise"),
            projectId: projectId,
            title: "プロジェクトサマリー作成",
            description: conciseTaskDescription,
            status: .backlog,
            priority: .high,
            assigneeId: conciseAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(conciseTask)
        print("✅ UC002: Task 2 created - assigned to 簡潔ライター (OUTPUT_B.md)")

        print("✅ UC002: All test data seeded successfully (1 project, 2 identical tasks)")

        // Debug: Verify data in database after seeding
        let allProjects = try await projectRepository.findAll()
        let allAgents = try await agentRepository.findAll()
        try? "After seeding - Projects: \(allProjects.map { $0.id.value }), Agents: \(allAgents.map { $0.id.value })\n".appendToFile("/tmp/uc002_seed_debug.txt")
    }
}
#endif
