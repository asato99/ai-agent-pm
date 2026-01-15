// Sources/App/Testing/Scenarios/UC011Seeder.swift
// UC011: プロジェクト一時停止テスト用シーダー
// 要件: docs/plan/PROJECT_PAUSE_FEATURE.md

#if DEBUG

import Foundation
import Domain
import Infrastructure

extension TestDataSeeder {

    /// UC011用のテストデータを生成（プロジェクト一時停止）
    /// 検証内容:
    /// - プロジェクト一時停止時にエージェントが停止する
    /// - プロジェクト再開後にエージェントが実行を再開する
    /// - セッション有効期限が短縮される
    func seedUC011Data() async throws {
        print("=== UC011 Test Data Configuration ===")
        print("Design: Project pause/resume with Runner integration")

        guard let projectAgentAssignmentRepository = projectAgentAssignmentRepository else {
            print("⚠️ UC011: projectAgentAssignmentRepository not available")
            return
        }

        // 作業ディレクトリを作成
        let fileManager = FileManager.default
        let workingDir = "/tmp/uc011_test"
        if !fileManager.fileExists(atPath: workingDir) {
            try fileManager.createDirectory(atPath: workingDir, withIntermediateDirectories: true)
        }
        // 既存のテスト出力ファイルを削除
        let stepFiles = ["step1.md", "step2.md", "step3.md", "complete.md", "test_output.md"]
        for file in stepFiles {
            let path = "\(workingDir)/\(file)"
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
        }

        // UC011用プロジェクト
        let projectId = ProjectID(value: "prj_uc011")
        let project = Project(
            id: projectId,
            name: "UC011 Pause Test",
            description: "プロジェクト一時停止テスト用",
            status: .active,
            workingDirectory: workingDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(project)
        print("✅ UC011: Project created - \(project.name)")

        // UC011用エージェント
        let agentId = AgentID(value: "agt_uc011_dev")
        let agent = Agent(
            id: agentId,
            name: "UC011開発者",
            role: "一時停止テスト用エージェント",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["Swift", "Markdown"],
            systemPrompt: "プロジェクト一時停止テスト用のエージェントです",
            kickMethod: .cli,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(agent)
        print("✅ UC011: Agent created - \(agent.name)")

        // Runner認証用クレデンシャル
        if let credentialRepository = credentialRepository {
            let credential = AgentCredential(
                agentId: agentId,
                rawPasskey: "test_passkey_uc011"
            )
            try credentialRepository.save(credential)
            print("✅ UC011: Credential created for \(agentId.value)")
        }

        // エージェントをプロジェクトに割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: agentId)
        print("✅ UC011: Agent assigned to project")

        // テスト用タスク（backlog状態、UIテストでin_progressに変更）
        // シンプルな「1ファイル作成」タスク
        let task = Task(
            id: TaskID(value: "tsk_uc011_main"),
            projectId: projectId,
            title: "UC011テストタスク",
            description: """
                【タスク指示】
                ファイル名: complete.md
                内容: プロジェクト一時停止テスト用のMarkdownファイルを作成してください。

                重要: ファイル内容には必ず 'uc011 integration test content' という文字列を含めること。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: agentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(task)
        print("✅ UC011: Task created - \(task.title)")

        print("✅ UC011: All test data seeded successfully")
    }
}
#endif
