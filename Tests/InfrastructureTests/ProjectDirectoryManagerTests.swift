// Tests/InfrastructureTests/ProjectDirectoryManagerTests.swift
// ProjectDirectoryManager - ログディレクトリ管理テスト
// 参照: docs/design/LOG_TRANSFER_DESIGN.md

import XCTest
@testable import Domain
@testable import Infrastructure

final class ProjectDirectoryManagerLogDirectoryTests: XCTestCase {
    private var sut: ProjectDirectoryManager!
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_project_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = ProjectDirectoryManager()
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        sut = nil
        try super.tearDownWithError()
    }

    // MARK: - getOrCreateLogDirectory Tests

    /// TEST 1: ログディレクトリが作成される
    func testGetOrCreateLogDirectory_CreatesDirectory() throws {
        let agentId = AgentID(value: "agt_test123")

        let logDir = try sut.getOrCreateLogDirectory(
            workingDirectory: tempDir.path,
            agentId: agentId
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: logDir.path))
        XCTAssertTrue(logDir.path.contains(".ai-pm/logs/agt_test123"))
    }

    /// TEST 2: 親ディレクトリ（logs）も作成される
    func testGetOrCreateLogDirectory_CreatesParentDirectories() throws {
        let agentId = AgentID(value: "agt_abc")

        let logDir = try sut.getOrCreateLogDirectory(
            workingDirectory: tempDir.path,
            agentId: agentId
        )

        // .ai-pm/logs ディレクトリも存在する
        let logsDir = logDir.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: logsDir.path))
        XCTAssertTrue(logsDir.path.hasSuffix("logs"))
    }

    /// TEST 3: 既存ディレクトリがあっても正常に動作
    func testGetOrCreateLogDirectory_ExistingDirectory_ReturnsPath() throws {
        let agentId = AgentID(value: "agt_test123")

        // 1回目の呼び出し
        let logDir1 = try sut.getOrCreateLogDirectory(
            workingDirectory: tempDir.path,
            agentId: agentId
        )

        // 2回目の呼び出し（既存）
        let logDir2 = try sut.getOrCreateLogDirectory(
            workingDirectory: tempDir.path,
            agentId: agentId
        )

        XCTAssertEqual(logDir1.path, logDir2.path)
    }

    /// TEST 4: workingDirectoryがnilの場合はエラー
    func testGetOrCreateLogDirectory_NilWorkingDirectory_ThrowsError() {
        let agentId = AgentID(value: "agt_test123")

        XCTAssertThrowsError(
            try sut.getOrCreateLogDirectory(workingDirectory: nil, agentId: agentId)
        ) { error in
            XCTAssertTrue(error is ProjectDirectoryManagerError)
            if case ProjectDirectoryManagerError.workingDirectoryNotSet = error {
                // 期待通り
            } else {
                XCTFail("Expected workingDirectoryNotSet error")
            }
        }
    }

    /// TEST 5: 異なるエージェントIDで異なるディレクトリが作成される
    func testGetOrCreateLogDirectory_DifferentAgents_CreatesSeparateDirectories() throws {
        let agent1 = AgentID(value: "agt_001")
        let agent2 = AgentID(value: "agt_002")

        let logDir1 = try sut.getOrCreateLogDirectory(
            workingDirectory: tempDir.path,
            agentId: agent1
        )
        let logDir2 = try sut.getOrCreateLogDirectory(
            workingDirectory: tempDir.path,
            agentId: agent2
        )

        XCTAssertNotEqual(logDir1.path, logDir2.path)
        XCTAssertTrue(logDir1.path.contains("agt_001"))
        XCTAssertTrue(logDir2.path.contains("agt_002"))
    }

    // MARK: - .gitignore Tests

    /// TEST 6: .gitignore に logs/ が含まれる
    func testGitignore_IncludesLogsDirectory() throws {
        let agentId = AgentID(value: "agt_test")

        // ログディレクトリを作成（これにより .ai-pm も作成される）
        _ = try sut.getOrCreateLogDirectory(
            workingDirectory: tempDir.path,
            agentId: agentId
        )

        // .gitignore を確認
        let gitignorePath = tempDir
            .appendingPathComponent(".ai-pm")
            .appendingPathComponent(".gitignore")

        XCTAssertTrue(FileManager.default.fileExists(atPath: gitignorePath.path))

        let content = try String(contentsOf: gitignorePath, encoding: .utf8)
        XCTAssertTrue(content.contains("logs/"), ".gitignore should contain 'logs/'")
    }
}
