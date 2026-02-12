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
        XCTAssertNotNil(properties["zip_file_path"], "zip_file_path property should be defined")

        // name, directory_name は frontmatter から自動抽出されるためオプショナル
        XCTAssertFalse(required.contains("name"), "name should not be required (auto-extracted from frontmatter)")
        XCTAssertFalse(required.contains("directory_name"), "directory_name should not be required (auto-extracted)")
        XCTAssertTrue(required.contains("session_token"), "session_token should be required")
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

        // Assert: archiveData からファイルを正しく抽出できること（SkillEditorView の loadSkillData と同等）
        let archiveService = SkillArchiveService()
        let extractedFiles = archiveService.extractAllFiles(from: saved!.archiveData)
        XCTAssertFalse(extractedFiles.isEmpty, "extractAllFiles should return non-empty dictionary")
        XCTAssertNotNil(extractedFiles["SKILL.md"], "SKILL.md should be extractable from archive")
        XCTAssertTrue(extractedFiles["SKILL.md"]!.contains("My Skill"), "SKILL.md should contain the original content")

        // Assert: getSkillMdContent でも取得できること
        let skillMdViaGet = archiveService.getSkillMdContent(from: saved!.archiveData)
        XCTAssertNotNil(skillMdViaGet, "getSkillMdContent should return content")
        XCTAssertTrue(skillMdViaGet!.contains("My Skill"), "getSkillMdContent should contain the original content")

        // Assert: listFiles でファイル一覧が取得できること
        let fileEntries = try archiveService.listFiles(archiveData: saved!.archiveData)
        XCTAssertFalse(fileEntries.isEmpty, "listFiles should return non-empty list")
        XCTAssertTrue(fileEntries.contains(where: { $0.path == "SKILL.md" }), "listFiles should contain SKILL.md")
    }

    // MARK: - Registration with Folder Path Tests

    /// folder_path パラメータでスキルが登録できること
    func testRegisterSkillWithFolderPath() throws {
        // Arrange: 一時フォルダにSKILL.md + サブファイルを配置
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_skill_folder_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillMd = "---\nname: Folder Skill\ndescription: From folder\n---\n# Folder Skill\nThis skill is loaded from a folder."
        try skillMd.write(to: tempDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let scriptsDir = tempDir.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try "echo hello".write(to: scriptsDir.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)

        // Arrange: 認証済みセッション
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

        // name が空 → エラー（SkillError.emptyName）
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
            XCTAssertTrue(error is SkillError, "Error should be SkillError: \(error)")
            XCTAssertEqual(error as? SkillError, .emptyName, "Error should be emptyName: \(error)")
        }

        // directory_name が不正形式 → エラー（SkillError.invalidDirectoryName）
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
            if case .invalidDirectoryName? = error as? SkillError {
                // OK
            } else {
                XCTFail("Error should be SkillError.invalidDirectoryName: \(error)")
            }
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

        // 同じ directory_name で2つ目を登録 → エラー（SkillError.directoryNameAlreadyExists）
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
            if case .directoryNameAlreadyExists? = error as? SkillError {
                // OK
            } else {
                XCTFail("Error should be SkillError.directoryNameAlreadyExists: \(error)")
            }
        }
    }

    // MARK: - ZIP File Path Tests

    /// zip_file_path パラメータでスキルが登録できること
    func testRegisterSkillWithZipFilePath() throws {
        // Arrange: 一時ZIPファイルを作成
        let archiveService = SkillArchiveService()
        let skillContent = """
            ---
            name: ZIP Skill
            description: A skill from ZIP
            ---
            # ZIP Skill
            This skill is loaded from a ZIP file.
            """
        let zipData = archiveService.createArchiveFromContent(skillContent)

        let tempDir = FileManager.default.temporaryDirectory
        let zipPath = tempDir.appendingPathComponent("zip-skill-\(UUID().uuidString).zip")
        try zipData.write(to: zipPath)
        defer { try? FileManager.default.removeItem(at: zipPath) }

        // エージェントとプロジェクトをDBに作成
        let agentId = AgentID(value: "agent-zip-test")
        let projectId = ProjectID(value: "proj-zip-test")
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO agents (id, name, role, type, status, role_type, created_at, updated_at)
                VALUES (?, ?, 'developer', 'worker', 'active', 'developer', datetime('now'), datetime('now'))
                """, arguments: [agentId.value, "ZIP Agent"])
            try db.execute(sql: """
                INSERT INTO projects (id, name, status, created_at, updated_at)
                VALUES (?, 'ZIP Project', 'active', datetime('now'), datetime('now'))
                """, arguments: [projectId.value])
        }

        let session = AgentSession(agentId: agentId, projectId: projectId, purpose: .task)
        let caller = CallerType.worker(agentId: agentId, session: session)

        // Act: zip_file_path のみで登録（name/directory_name は自動抽出）
        let result = try mcpServer.executeTool(
            name: "register_skill",
            arguments: [
                "session_token": session.token,
                "zip_file_path": zipPath.path
            ],
            caller: caller
        ) as! [String: Any]

        // Assert: 成功レスポンス
        XCTAssertEqual(result["status"] as? String, "success")
        XCTAssertNotNil(result["skill_id"] as? String)
        // frontmatter の name が使用される
        XCTAssertEqual(result["name"] as? String, "ZIP Skill")

        // Assert: DBに保存されている
        let repo = SkillDefinitionRepository(database: db)
        let dirName = result["directory_name"] as! String
        let saved = try repo.findByDirectoryName(dirName)
        XCTAssertNotNil(saved, "Skill should be saved in database")
        XCTAssertEqual(saved?.name, "ZIP Skill")
        XCTAssertEqual(saved?.description, "A skill from ZIP")
    }

    // MARK: - Override Tests

    /// name / directory_name 引数が frontmatter の値をオーバーライドすること
    func testRegisterSkillWithOverrides() throws {
        // Arrange
        let agentId = AgentID(value: "agent-override-test")
        let projectId = ProjectID(value: "proj-override-test")
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO agents (id, name, role, type, status, role_type, created_at, updated_at)
                VALUES (?, ?, 'developer', 'worker', 'active', 'developer', datetime('now'), datetime('now'))
                """, arguments: [agentId.value, "Override Agent"])
            try db.execute(sql: """
                INSERT INTO projects (id, name, status, created_at, updated_at)
                VALUES (?, 'Override Project', 'active', datetime('now'), datetime('now'))
                """, arguments: [projectId.value])
        }

        let session = AgentSession(agentId: agentId, projectId: projectId, purpose: .task)
        let caller = CallerType.worker(agentId: agentId, session: session)

        // frontmatter に name/description を含むコンテンツ
        let skillContent = """
            ---
            name: Original Name
            description: Original description
            ---
            # Skill
            """

        // Act: name / directory_name / description をオーバーライド
        let result = try mcpServer.executeTool(
            name: "register_skill",
            arguments: [
                "session_token": session.token,
                "skill_md_content": skillContent,
                "name": "Overridden Name",
                "directory_name": "overridden-dir",
                "description": "Overridden description"
            ],
            caller: caller
        ) as! [String: Any]

        // Assert: オーバーライドされた値が使用される
        XCTAssertEqual(result["status"] as? String, "success")
        XCTAssertEqual(result["name"] as? String, "Overridden Name")
        XCTAssertEqual(result["directory_name"] as? String, "overridden-dir")

        let repo = SkillDefinitionRepository(database: db)
        let saved = try repo.findByDirectoryName("overridden-dir")
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.name, "Overridden Name")
        XCTAssertEqual(saved?.description, "Overridden description")
    }
}
