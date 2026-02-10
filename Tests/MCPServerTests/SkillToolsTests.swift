// Tests/MCPServerTests/SkillToolsTests.swift
// register_skill MCPツールのテスト

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

/// register_skill ツールのテスト
final class SkillToolsTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_skill_tools_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)
        mcpServer = MCPServer(database: db)
    }

    override func tearDownWithError() throws {
        mcpServer = nil
        db = nil
    }

    // MARK: - Tool Definition Tests

    /// ToolDefinitions.all() に register_skill が含まれること
    func testRegisterSkillToolIsDefined() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("register_skill"), "register_skill should be defined in ToolDefinitions")

        // inputSchema に必須パラメータが定義されていること
        let tool = ToolDefinitions.registerSkill
        XCTAssertEqual(tool["name"] as? String, "register_skill")

        let schema = tool["inputSchema"] as! [String: Any]
        let properties = schema["properties"] as! [String: Any]
        let required = schema["required"] as! [String]

        XCTAssertNotNil(properties["name"], "name property should be defined")
        XCTAssertNotNil(properties["directory_name"], "directory_name property should be defined")
        XCTAssertNotNil(properties["skill_md_content"], "skill_md_content property should be defined")
        XCTAssertNotNil(properties["folder_path"], "folder_path property should be defined")
        XCTAssertNotNil(properties["description"], "description property should be defined")

        XCTAssertTrue(required.contains("name"), "name should be required")
        XCTAssertTrue(required.contains("directory_name"), "directory_name should be required")
    }

    // MARK: - Permission Tests

    /// register_skill の権限が .authenticated であること
    func testRegisterSkillPermissionIsAuthenticated() {
        XCTAssertEqual(
            ToolAuthorization.permissions["register_skill"],
            .authenticated,
            "register_skill should require authenticated permission"
        )
    }

    // MARK: - Registration with Content Tests

    /// skill_md_content パラメータでスキルが登録できること
    func testRegisterSkillWithContent() throws {
        // Arrange: 認証済みセッションを作成
        let agentId = AgentID(value: "agent-test-skill")
        let projectId = ProjectID(value: "proj-test")

        // エージェントとプロジェクトをDBに作成
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO agents (id, name, role, type, status, role_type, created_at, updated_at)
                VALUES (?, ?, 'developer', 'worker', 'active', 'developer', datetime('now'), datetime('now'))
                """, arguments: [agentId.value, "Test Agent"])
            try db.execute(sql: """
                INSERT INTO projects (id, name, status, created_at, updated_at)
                VALUES (?, 'Test Project', 'active', datetime('now'), datetime('now'))
                """, arguments: [projectId.value])
        }

        let session = AgentSession(agentId: agentId, projectId: projectId, purpose: .task)
        let caller = CallerType.worker(agentId: agentId, session: session)

        let skillMdContent = """
            # My Skill
            This is a test skill.
            ## Usage
            Use it wisely.
            """

        // Act
        let result = try mcpServer.executeTool(
            name: "register_skill",
            arguments: [
                "session_token": session.token,
                "name": "My Test Skill",
                "directory_name": "my-test-skill",
                "description": "A test skill for unit testing",
                "skill_md_content": skillMdContent
            ],
            caller: caller
        ) as! [String: Any]

        // Assert: 成功レスポンス
        XCTAssertEqual(result["status"] as? String, "success")
        XCTAssertNotNil(result["skill_id"] as? String)
        XCTAssertEqual(result["directory_name"] as? String, "my-test-skill")

        // Assert: DBに保存されている
        let repo = SkillDefinitionRepository(database: db)
        let saved = try repo.findByDirectoryName("my-test-skill")
        XCTAssertNotNil(saved, "Skill should be saved in database")
        XCTAssertEqual(saved?.name, "My Test Skill")
        XCTAssertEqual(saved?.description, "A test skill for unit testing")
        XCTAssertFalse(saved!.archiveData.isEmpty, "Archive data should not be empty")
    }

    // MARK: - Registration with Folder Path Tests

    /// folder_path パラメータでスキルが登録できること
    func testRegisterSkillWithFolderPath() throws {
        // Arrange: 一時フォルダにSKILL.md + サブファイルを配置
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_skill_folder_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillMd = "# Folder Skill\nThis skill is loaded from a folder."
        try skillMd.write(to: tempDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let scriptsDir = tempDir.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try "echo hello".write(to: scriptsDir.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)

        // エージェントとプロジェクトをDBに作成
        let agentId = AgentID(value: "agent-folder-test")
        let projectId = ProjectID(value: "proj-folder-test")
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO agents (id, name, role, type, status, role_type, created_at, updated_at)
                VALUES (?, ?, 'developer', 'worker', 'active', 'developer', datetime('now'), datetime('now'))
                """, arguments: [agentId.value, "Folder Agent"])
            try db.execute(sql: """
                INSERT INTO projects (id, name, status, created_at, updated_at)
                VALUES (?, 'Folder Project', 'active', datetime('now'), datetime('now'))
                """, arguments: [projectId.value])
        }

        let session = AgentSession(agentId: agentId, projectId: projectId, purpose: .task)
        let caller = CallerType.worker(agentId: agentId, session: session)

        // Act
        let result = try mcpServer.executeTool(
            name: "register_skill",
            arguments: [
                "session_token": session.token,
                "name": "Folder Skill",
                "directory_name": "folder-skill",
                "folder_path": tempDir.path
            ],
            caller: caller
        ) as! [String: Any]

        // Assert
        XCTAssertEqual(result["status"] as? String, "success")
        XCTAssertNotNil(result["skill_id"] as? String)

        let repo = SkillDefinitionRepository(database: db)
        let saved = try repo.findByDirectoryName("folder-skill")
        XCTAssertNotNil(saved, "Skill should be saved from folder path")
        XCTAssertEqual(saved?.name, "Folder Skill")
        XCTAssertFalse(saved!.archiveData.isEmpty, "Archive data should contain folder contents")
    }

    // MARK: - Validation Tests

    /// バリデーションエラーのテスト
    func testRegisterSkillValidation() throws {
        let agentId = AgentID(value: "agent-val-test")
        let projectId = ProjectID(value: "proj-val-test")
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO agents (id, name, role, type, status, role_type, created_at, updated_at)
                VALUES (?, ?, 'developer', 'worker', 'active', 'developer', datetime('now'), datetime('now'))
                """, arguments: [agentId.value, "Val Agent"])
            try db.execute(sql: """
                INSERT INTO projects (id, name, status, created_at, updated_at)
                VALUES (?, 'Val Project', 'active', datetime('now'), datetime('now'))
                """, arguments: [projectId.value])
        }

        let session = AgentSession(agentId: agentId, projectId: projectId, purpose: .task)
        let caller = CallerType.worker(agentId: agentId, session: session)

        // name が空 → エラー
        XCTAssertThrowsError(try mcpServer.executeTool(
            name: "register_skill",
            arguments: [
                "session_token": session.token,
                "name": "",
                "directory_name": "valid-name",
                "skill_md_content": "# Skill"
            ],
            caller: caller
        )) { error in
            XCTAssertTrue("\(error)".contains("name"), "Error should mention name: \(error)")
        }

        // directory_name が不正形式 → エラー
        XCTAssertThrowsError(try mcpServer.executeTool(
            name: "register_skill",
            arguments: [
                "session_token": session.token,
                "name": "Valid Name",
                "directory_name": "INVALID NAME!",
                "skill_md_content": "# Skill"
            ],
            caller: caller
        )) { error in
            XCTAssertTrue("\(error)".contains("directory_name"), "Error should mention directory_name: \(error)")
        }

        // skill_md_content と folder_path の両方未指定 → エラー
        XCTAssertThrowsError(try mcpServer.executeTool(
            name: "register_skill",
            arguments: [
                "session_token": session.token,
                "name": "Valid Name",
                "directory_name": "valid-name"
            ],
            caller: caller
        )) { error in
            XCTAssertTrue("\(error)".contains("skill_md_content") || "\(error)".contains("folder_path"),
                          "Error should mention missing content source: \(error)")
        }

        // skill_md_content と folder_path の両方指定 → エラー
        XCTAssertThrowsError(try mcpServer.executeTool(
            name: "register_skill",
            arguments: [
                "session_token": session.token,
                "name": "Valid Name",
                "directory_name": "valid-name",
                "skill_md_content": "# Skill",
                "folder_path": "/tmp/nonexistent"
            ],
            caller: caller
        )) { error in
            XCTAssertTrue("\(error)".contains("skill_md_content") || "\(error)".contains("folder_path") || "\(error)".contains("exclusive"),
                          "Error should mention mutually exclusive parameters: \(error)")
        }

        // directory_name 重複 → エラー
        // まず1つ登録
        _ = try mcpServer.executeTool(
            name: "register_skill",
            arguments: [
                "session_token": session.token,
                "name": "First Skill",
                "directory_name": "dup-test",
                "skill_md_content": "# First"
            ],
            caller: caller
        )

        // 同じ directory_name で2つ目を登録 → エラー
        XCTAssertThrowsError(try mcpServer.executeTool(
            name: "register_skill",
            arguments: [
                "session_token": session.token,
                "name": "Second Skill",
                "directory_name": "dup-test",
                "skill_md_content": "# Second"
            ],
            caller: caller
        )) { error in
            XCTAssertTrue("\(error)".contains("dup") || "\(error)".contains("already exists") || "\(error)".contains("directory_name"),
                          "Error should mention duplicate: \(error)")
        }
    }
}
