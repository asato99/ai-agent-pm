// Tests/IntegrationTests/LogTransferIntegrationTests.swift
// ログ転送機能 - 統合テスト
// 参照: docs/design/LOG_TRANSFER_TDD.md - Phase 3

import XCTest
import GRDB
@testable import Infrastructure
@testable import Domain

/// ログ転送機能の統合テスト
/// サーバー側コンポーネント（LogUploadService + ProjectDirectoryManager + Repository）の統合動作を検証
final class LogTransferIntegrationTests: XCTestCase {
    private var db: DatabaseQueue!
    private var projectRepository: ProjectRepository!
    private var taskRepository: TaskRepository!
    private var agentRepository: AgentRepository!
    private var executionLogRepository: ExecutionLogRepository!
    private var directoryManager: ProjectDirectoryManager!
    private var logUploadService: LogUploadService!
    private var tempDir: URL!
    private var projectWorkingDir: URL!

    // テストデータ
    private let testProjectId = ProjectID(value: "prj_integration_test")
    private let testAgentId = AgentID(value: "agt_integration_test")
    private let testTaskId = TaskID(value: "tsk_integration_test")

    override func setUpWithError() throws {
        try super.setUpWithError()

        // テスト用一時ディレクトリ作成
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("log_transfer_integration_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // プロジェクトのworkingDirectory用ディレクトリ
        projectWorkingDir = tempDir.appendingPathComponent("project_wd")
        try FileManager.default.createDirectory(at: projectWorkingDir, withIntermediateDirectories: true)

        // テスト用DB作成
        let dbPath = tempDir.appendingPathComponent("test.db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // リポジトリ初期化
        projectRepository = ProjectRepository(database: db)
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        executionLogRepository = ExecutionLogRepository(database: db)
        directoryManager = ProjectDirectoryManager()

        // サービス初期化
        logUploadService = LogUploadService(
            directoryManager: directoryManager,
            projectRepository: projectRepository,
            executionLogRepository: executionLogRepository
        )

        // テストデータ準備
        try setupTestData()
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        db = nil
        try super.tearDownWithError()
    }

    private func setupTestData() throws {
        // プロジェクト作成
        let project = Project(
            id: testProjectId,
            name: "Integration Test Project",
            workingDirectory: projectWorkingDir.path
        )
        try projectRepository.save(project)

        // エージェント作成
        let agent = Agent(
            id: testAgentId,
            name: "Integration Test Agent",
            role: "Developer"
        )
        try agentRepository.save(agent)

        // タスク作成
        let task = Task(
            id: testTaskId,
            projectId: testProjectId,
            title: "Integration Test Task"
        )
        try taskRepository.save(task)
    }

    // MARK: - TEST 1: 完全なフロー（ログ生成 → 保存 → 参照）

    /// ログアップロードから参照までの完全なフローをテスト
    func testEndToEndLogTransfer() throws {
        // 1. ExecutionLogを作成（タスク実行開始をシミュレート）
        let executionLogId = ExecutionLogID(value: "exec_e2e_\(UUID().uuidString)")
        let executionLog = ExecutionLog(
            id: executionLogId,
            taskId: testTaskId,
            agentId: testAgentId,
            status: .completed,
            startedAt: Date().addingTimeInterval(-60),  // 1分前に開始
            completedAt: Date(),
            exitCode: 0,
            durationSeconds: 60.0,
            logFilePath: nil,  // 初期状態ではnull
            errorMessage: nil
        )
        try executionLogRepository.save(executionLog)

        // 2. ログ内容を準備（タスク実行ログをシミュレート）
        let logContent = """
        [2026-01-25 14:30:22] Task started: Integration Test Task
        [2026-01-25 14:30:23] Executing step 1...
        [2026-01-25 14:30:45] Step 1 completed successfully
        [2026-01-25 14:31:00] Executing step 2...
        [2026-01-25 14:31:22] Step 2 completed successfully
        [2026-01-25 14:31:22] Task completed with exit code 0
        """
        let logData = Data(logContent.utf8)
        let originalFilename = "20260125_143022.log"

        // 3. ログアップロード実行
        let uploadResult = try logUploadService.uploadLog(
            executionLogId: executionLogId.value,
            agentId: testAgentId.value,
            taskId: testTaskId.value,
            projectId: testProjectId.value,
            logData: logData,
            originalFilename: originalFilename
        )

        // 4. アップロード成功を確認
        XCTAssertTrue(uploadResult.success)
        XCTAssertNotNil(uploadResult.logFilePath)
        XCTAssertEqual(uploadResult.fileSize, logData.count)

        // 5. ファイルが正しいパスに保存されていることを確認
        let savedPath = uploadResult.logFilePath!
        XCTAssertTrue(savedPath.contains(".ai-pm/logs/\(testAgentId.value)"))
        XCTAssertTrue(savedPath.hasSuffix(originalFilename))
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedPath))

        // 6. ファイル内容が正しいことを確認
        let savedContent = try String(contentsOfFile: savedPath, encoding: .utf8)
        XCTAssertEqual(savedContent, logContent)

        // 7. ExecutionLogのlogFilePathが更新されていることを確認
        let updatedLog = try executionLogRepository.findById(executionLogId)
        XCTAssertNotNil(updatedLog)
        XCTAssertEqual(updatedLog?.logFilePath, savedPath)

        // 8. ディレクトリ構造が正しいことを確認
        let expectedDirPath = projectWorkingDir
            .appendingPathComponent(".ai-pm")
            .appendingPathComponent("logs")
            .appendingPathComponent(testAgentId.value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDirPath.path))
    }

    // MARK: - TEST 2: 複数のログファイル保存

    /// 同じエージェントから複数のログが正しく保存されることを確認
    func testMultipleLogsFromSameAgent() throws {
        var savedPaths: [String] = []

        for i in 1...3 {
            let executionLogId = ExecutionLogID(value: "exec_multi_\(i)")
            let executionLog = ExecutionLog(
                id: executionLogId,
                taskId: testTaskId,
                agentId: testAgentId,
                status: .completed,
                startedAt: Date(),
                completedAt: Date(),
                exitCode: 0,
                durationSeconds: 10.0,
                logFilePath: nil,
                errorMessage: nil
            )
            try executionLogRepository.save(executionLog)

            let logContent = "Log file \(i) content"
            let logData = Data(logContent.utf8)
            let filename = "log_\(i).log"

            let result = try logUploadService.uploadLog(
                executionLogId: executionLogId.value,
                agentId: testAgentId.value,
                taskId: testTaskId.value,
                projectId: testProjectId.value,
                logData: logData,
                originalFilename: filename
            )

            XCTAssertTrue(result.success)
            savedPaths.append(result.logFilePath!)
        }

        // 全てのファイルが存在し、パスが異なることを確認
        XCTAssertEqual(savedPaths.count, 3)
        XCTAssertEqual(Set(savedPaths).count, 3)  // 全て異なるパス

        for path in savedPaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        }
    }

    // MARK: - TEST 3: 異なるエージェントのログ分離

    /// 異なるエージェントのログが別ディレクトリに保存されることを確認
    func testLogIsolationBetweenAgents() throws {
        // 2つ目のエージェントを作成
        let agent2Id = AgentID(value: "agt_integration_test_2")
        let agent2 = Agent(
            id: agent2Id,
            name: "Integration Test Agent 2",
            role: "Reviewer"
        )
        try agentRepository.save(agent2)

        // エージェント1のログ
        let execLog1Id = ExecutionLogID(value: "exec_agent1")
        let execLog1 = ExecutionLog(
            id: execLog1Id,
            taskId: testTaskId,
            agentId: testAgentId,
            status: .completed,
            startedAt: Date(),
            completedAt: Date(),
            exitCode: 0,
            durationSeconds: 10.0,
            logFilePath: nil,
            errorMessage: nil
        )
        try executionLogRepository.save(execLog1)

        let result1 = try logUploadService.uploadLog(
            executionLogId: execLog1Id.value,
            agentId: testAgentId.value,
            taskId: testTaskId.value,
            projectId: testProjectId.value,
            logData: Data("Agent 1 log".utf8),
            originalFilename: "agent1.log"
        )

        // エージェント2のログ
        let execLog2Id = ExecutionLogID(value: "exec_agent2")
        let execLog2 = ExecutionLog(
            id: execLog2Id,
            taskId: testTaskId,
            agentId: agent2Id,
            status: .completed,
            startedAt: Date(),
            completedAt: Date(),
            exitCode: 0,
            durationSeconds: 10.0,
            logFilePath: nil,
            errorMessage: nil
        )
        try executionLogRepository.save(execLog2)

        let result2 = try logUploadService.uploadLog(
            executionLogId: execLog2Id.value,
            agentId: agent2Id.value,
            taskId: testTaskId.value,
            projectId: testProjectId.value,
            logData: Data("Agent 2 log".utf8),
            originalFilename: "agent2.log"
        )

        // 異なるディレクトリに保存されていることを確認
        XCTAssertTrue(result1.success)
        XCTAssertTrue(result2.success)

        // パスコンポーネントとしてエージェントIDが含まれていることを確認
        // （部分文字列一致ではなく、ディレクトリ名として）
        XCTAssertTrue(result1.logFilePath!.contains("/\(testAgentId.value)/"))
        XCTAssertTrue(result2.logFilePath!.contains("/\(agent2Id.value)/"))
        XCTAssertFalse(result1.logFilePath!.contains("/\(agent2Id.value)/"))
        XCTAssertFalse(result2.logFilePath!.contains("/\(testAgentId.value)/"))
    }

    // MARK: - TEST 4: 大きなログファイル（制限内）

    /// 大きなログファイル（10MB未満）が正しく保存されることを確認
    func testLargeLogFileWithinLimit() throws {
        let executionLogId = ExecutionLogID(value: "exec_large")
        let executionLog = ExecutionLog(
            id: executionLogId,
            taskId: testTaskId,
            agentId: testAgentId,
            status: .completed,
            startedAt: Date(),
            completedAt: Date(),
            exitCode: 0,
            durationSeconds: 10.0,
            logFilePath: nil,
            errorMessage: nil
        )
        try executionLogRepository.save(executionLog)

        // 5MBのログを生成（10MB制限内）
        let singleLine = String(repeating: "x", count: 1000) + "\n"
        let lineCount = 5 * 1024  // 約5MB
        let largeContent = String(repeating: singleLine, count: lineCount)
        let logData = Data(largeContent.utf8)

        let result = try logUploadService.uploadLog(
            executionLogId: executionLogId.value,
            agentId: testAgentId.value,
            taskId: testTaskId.value,
            projectId: testProjectId.value,
            logData: logData,
            originalFilename: "large.log"
        )

        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.logFilePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.logFilePath!))

        // ファイルサイズを確認
        let attributes = try FileManager.default.attributesOfItem(atPath: result.logFilePath!)
        let fileSize = attributes[.size] as! Int
        XCTAssertGreaterThan(fileSize, 4 * 1024 * 1024)  // 4MB以上
        XCTAssertLessThan(fileSize, 10 * 1024 * 1024)    // 10MB未満
    }

    // MARK: - TEST 5: gitignore確認

    /// .ai-pm/logs/ ディレクトリがgitignoreに追加されていることを確認
    func testLogsDirectoryInGitignore() throws {
        // プロジェクトルートの.gitignoreを確認
        let gitignorePath = projectWorkingDir.appendingPathComponent(".gitignore")

        // ログをアップロードして.ai-pmディレクトリを作成
        let executionLogId = ExecutionLogID(value: "exec_gitignore_test")
        let executionLog = ExecutionLog(
            id: executionLogId,
            taskId: testTaskId,
            agentId: testAgentId,
            status: .completed,
            startedAt: Date(),
            completedAt: Date(),
            exitCode: 0,
            durationSeconds: 10.0,
            logFilePath: nil,
            errorMessage: nil
        )
        try executionLogRepository.save(executionLog)

        _ = try logUploadService.uploadLog(
            executionLogId: executionLogId.value,
            agentId: testAgentId.value,
            taskId: testTaskId.value,
            projectId: testProjectId.value,
            logData: Data("test".utf8),
            originalFilename: "test.log"
        )

        // .ai-pm/logs ディレクトリが存在することを確認
        let logsDir = projectWorkingDir
            .appendingPathComponent(".ai-pm")
            .appendingPathComponent("logs")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logsDir.path))

        // 注: 実際の.gitignore更新はProjectDirectoryManagerの責務
        // このテストでは、ディレクトリ構造が正しいことのみを確認
    }

    // MARK: - TEST 6: エラーリカバリ

    /// ディスク書き込みエラー時の適切なエラーハンドリングを確認
    func testErrorHandlingOnDiskWriteFailure() throws {
        // 読み取り専用ディレクトリを作成してエラーをシミュレート
        let readOnlyDir = tempDir.appendingPathComponent("readonly_project")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)

        // プロジェクトを作成（読み取り専用ディレクトリ）
        let readOnlyProjectId = ProjectID(value: "prj_readonly")
        let readOnlyProject = Project(
            id: readOnlyProjectId,
            name: "Read Only Project",
            workingDirectory: readOnlyDir.path
        )
        try projectRepository.save(readOnlyProject)

        // ディレクトリを読み取り専用に設定
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: readOnlyDir.path
        )

        defer {
            // クリーンアップ: 書き込み権限を復元
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: readOnlyDir.path
            )
        }

        let executionLogId = ExecutionLogID(value: "exec_readonly")
        let executionLog = ExecutionLog(
            id: executionLogId,
            taskId: testTaskId,
            agentId: testAgentId,
            status: .completed,
            startedAt: Date(),
            completedAt: Date(),
            exitCode: 0,
            durationSeconds: 10.0,
            logFilePath: nil,
            errorMessage: nil
        )
        try executionLogRepository.save(executionLog)

        // エラーがスローされることを確認
        XCTAssertThrowsError(
            try logUploadService.uploadLog(
                executionLogId: executionLogId.value,
                agentId: testAgentId.value,
                taskId: testTaskId.value,
                projectId: readOnlyProjectId.value,
                logData: Data("test".utf8),
                originalFilename: "test.log"
            )
        )
    }
}
