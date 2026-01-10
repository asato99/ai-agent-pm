// Sources/App/Testing/Scenarios/UC004Seeder.swift
// UC004: 複数プロジェクト×同一エージェントテスト用シーダー

#if DEBUG

import Foundation
import Domain
import Infrastructure

extension TestDataSeeder {

    /// UC004用のテストデータを生成（複数プロジェクト×同一エージェント）
    /// - 2つのプロジェクト（フロントエンド、バックエンド）
    /// - 1つのエージェント（両プロジェクトに割り当て）
    /// - 各プロジェクトに1タスク
    ///
    /// 検証内容:
    /// - 同一エージェントが複数プロジェクトに割り当て可能
    /// - 各プロジェクトで異なるworking_directoryで実行
    /// - list_active_projects_with_agents APIが正しいマッピングを返す
    func seedUC004Data() async throws {
        print("=== UC004 Test Data Configuration ===")
        print("Design: 2 projects + 1 agent assigned to both")

        guard let projectAgentAssignmentRepository = projectAgentAssignmentRepository else {
            print("⚠️ UC004: projectAgentAssignmentRepository not available")
            return
        }

        // 作業ディレクトリを作成
        let fileManager = FileManager.default
        let frontendDir = "/tmp/uc004/frontend"
        let backendDir = "/tmp/uc004/backend"
        if !fileManager.fileExists(atPath: frontendDir) {
            try fileManager.createDirectory(atPath: frontendDir, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: backendDir) {
            try fileManager.createDirectory(atPath: backendDir, withIntermediateDirectories: true)
        }

        // UC004用プロジェクト1: フロントエンド
        let frontendProjectId = ProjectID(value: "prj_uc004_fe")
        let frontendProject = Project(
            id: frontendProjectId,
            name: "UC004 Frontend",
            description: "フロントエンドアプリ（UC004テスト用）",
            status: .active,
            workingDirectory: frontendDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(frontendProject)
        print("✅ UC004: Frontend project created - \(frontendProject.name)")

        // UC004用プロジェクト2: バックエンド
        let backendProjectId = ProjectID(value: "prj_uc004_be")
        let backendProject = Project(
            id: backendProjectId,
            name: "UC004 Backend",
            description: "バックエンドAPI（UC004テスト用）",
            status: .active,
            workingDirectory: backendDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(backendProject)
        print("✅ UC004: Backend project created - \(backendProject.name)")

        // UC004用エージェント: 両プロジェクトに割り当てられる開発者
        let devAgentId = AgentID(value: "agt_uc004_dev")
        let devAgent = Agent(
            id: devAgentId,
            name: "UC004開発者",
            role: "フルスタック開発者",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 2,  // 並列2タスクまで可能
            capabilities: ["TypeScript", "Python", "Swift"],
            systemPrompt: "フロントエンドとバックエンド両方の開発を担当するエージェントです",
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(devAgent)
        print("✅ UC004: Developer agent created - \(devAgent.name)")

        // Runner認証用クレデンシャル
        if let credentialRepository = credentialRepository {
            let credential = AgentCredential(
                agentId: devAgentId,
                rawPasskey: "test_passkey_uc004"
            )
            try credentialRepository.save(credential)
            print("✅ UC004: Credential created for \(devAgentId.value)")
        }

        // エージェントを両プロジェクトに割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: frontendProjectId, agentId: devAgentId)
        print("✅ UC004: Agent assigned to Frontend project")
        _ = try projectAgentAssignmentRepository.assign(projectId: backendProjectId, agentId: devAgentId)
        print("✅ UC004: Agent assigned to Backend project")

        // フロントエンドプロジェクトのタスク
        let frontendTask = Task(
            id: TaskID(value: "tsk_uc004_fe"),
            projectId: frontendProjectId,
            title: "README作成（Frontend）",
            description: """
                【タスク指示】
                ファイル名: README.md
                内容: フロントエンドプロジェクトのREADMEを作成してください。
                プロジェクト名とworking_directoryのパスを含めてください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: devAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(frontendTask)
        print("✅ UC004: Frontend task created")

        // バックエンドプロジェクトのタスク
        let backendTask = Task(
            id: TaskID(value: "tsk_uc004_be"),
            projectId: backendProjectId,
            title: "README作成（Backend）",
            description: """
                【タスク指示】
                ファイル名: README.md
                内容: バックエンドプロジェクトのREADMEを作成してください。
                プロジェクト名とworking_directoryのパスを含めてください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: devAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(backendTask)
        print("✅ UC004: Backend task created")

        print("✅ UC004: All test data seeded successfully (2 projects, 1 agent, 2 tasks)")
    }
}
#endif
