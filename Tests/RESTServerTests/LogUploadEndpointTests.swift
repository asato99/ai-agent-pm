// Tests/RESTServerTests/LogUploadEndpointTests.swift
// ログアップロードAPIエンドポイント - テスト
// 参照: docs/design/LOG_TRANSFER_DESIGN.md

import XCTest
import GRDB
@testable import Infrastructure
@testable import Domain

/// POST /api/v1/execution-logs/upload エンドポイントのテスト
final class LogUploadEndpointTests: XCTestCase {
    private var db: DatabaseQueue!
    private var projectRepository: ProjectRepository!
    private var taskRepository: TaskRepository!
    private var agentRepository: AgentRepository!
    private var executionLogRepository: ExecutionLogRepository!
    private var appSettingsRepository: AppSettingsRepository!
    private var directoryManager: ProjectDirectoryManager!
    private var tempDir: URL!

    // テストデータ
    private let testProjectId = ProjectID(value: "prj_log_test")
    private let testAgentId = AgentID(value: "agt_log_test")
    private let testTaskId = TaskID(value: "tsk_log_test")
    private let testExecutionLogId = ExecutionLogID(value: "exec_log_test")
    private let testCoordinatorToken = "test-coordinator-token-12345"

    override func setUpWithError() throws {
        try super.setUpWithError()

        // テスト用一時ディレクトリ作成
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("log_upload_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // テスト用DB作成
        let dbPath = tempDir.appendingPathComponent("test.db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // リポジトリ初期化
        projectRepository = ProjectRepository(database: db)
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        executionLogRepository = ExecutionLogRepository(database: db)
        appSettingsRepository = AppSettingsRepository(database: db)
        directoryManager = ProjectDirectoryManager()

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
        // プロジェクト作成（workingDirectory設定済み）
        let project = Project(
            id: testProjectId,
            name: "Log Upload Test Project",
            workingDirectory: tempDir.path
        )
        try projectRepository.save(project)

        // エージェント作成（ExecutionLogの外部キー用）
        let agent = Agent(
            id: testAgentId,
            name: "Test Agent",
            role: "Developer"
        )
        try agentRepository.save(agent)

        // タスク作成（ExecutionLogの外部キー用）
        let task = Task(
            id: testTaskId,
            projectId: testProjectId,
            title: "Test Task"
        )
        try taskRepository.save(task)

        // 実行ログ作成（logFilePathは未設定）
        // DB復元用イニシャライザで completed 状態として作成
        let executionLog = ExecutionLog(
            id: testExecutionLogId,
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

        // Coordinator Token設定
        // coordinatorToken setterはprivateなので、新しいインスタンスを作成
        let settings = AppSettings(
            coordinatorToken: testCoordinatorToken
        )
        try appSettingsRepository.save(settings)
    }

    // MARK: - LogUploadService Tests (Unit Tests)

    /// TEST 1: ログアップロードサービスが正しいパスを生成する
    func testLogUploadService_GeneratesCorrectPath() throws {
        let service = LogUploadService(
            directoryManager: directoryManager,
            projectRepository: projectRepository,
            executionLogRepository: executionLogRepository
        )

        let logContent = Data("Test log content\nLine 2\n".utf8)

        let result = try service.uploadLog(
            executionLogId: testExecutionLogId.value,
            agentId: testAgentId.value,
            taskId: testTaskId.value,
            projectId: testProjectId.value,
            logData: logContent,
            originalFilename: "20260125_143022.log"
        )

        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.logFilePath)
        XCTAssertTrue(result.logFilePath!.contains(".ai-pm/logs/\(testAgentId.value)"))
        XCTAssertTrue(result.logFilePath!.hasSuffix("20260125_143022.log"))
    }

    /// TEST 2: ログファイルが実際に作成される
    func testLogUploadService_CreatesLogFile() throws {
        let service = LogUploadService(
            directoryManager: directoryManager,
            projectRepository: projectRepository,
            executionLogRepository: executionLogRepository
        )

        let logContent = "Test log content for file creation"
        let logData = Data(logContent.utf8)

        let result = try service.uploadLog(
            executionLogId: testExecutionLogId.value,
            agentId: testAgentId.value,
            taskId: testTaskId.value,
            projectId: testProjectId.value,
            logData: logData,
            originalFilename: "test.log"
        )

        XCTAssertTrue(result.success)

        // ファイルが存在することを確認
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.logFilePath!))

        // 内容が正しいことを確認
        let savedContent = try String(contentsOfFile: result.logFilePath!, encoding: .utf8)
        XCTAssertEqual(savedContent, logContent)
    }

    /// TEST 3: ExecutionLogのlogFilePathが更新される
    func testLogUploadService_UpdatesExecutionLog() throws {
        let service = LogUploadService(
            directoryManager: directoryManager,
            projectRepository: projectRepository,
            executionLogRepository: executionLogRepository
        )

        let logData = Data("Test log".utf8)

        _ = try service.uploadLog(
            executionLogId: testExecutionLogId.value,
            agentId: testAgentId.value,
            taskId: testTaskId.value,
            projectId: testProjectId.value,
            logData: logData,
            originalFilename: "test.log"
        )

        // ExecutionLogが更新されていることを確認
        let updatedLog = try executionLogRepository.findById(testExecutionLogId)
        XCTAssertNotNil(updatedLog?.logFilePath)
        XCTAssertTrue(updatedLog!.logFilePath!.contains(".ai-pm/logs"))
    }

    /// TEST 4: プロジェクトが見つからない場合はエラー
    func testLogUploadService_ProjectNotFound_ThrowsError() throws {
        let service = LogUploadService(
            directoryManager: directoryManager,
            projectRepository: projectRepository,
            executionLogRepository: executionLogRepository
        )

        let logData = Data("Test log".utf8)

        XCTAssertThrowsError(
            try service.uploadLog(
                executionLogId: "exec_123",
                agentId: "agt_456",
                taskId: "task_789",
                projectId: "nonexistent_project",
                logData: logData,
                originalFilename: "test.log"
            )
        ) { error in
            XCTAssertTrue(error is LogUploadError)
            if case LogUploadError.projectNotFound = error {
                // 期待通り
            } else {
                XCTFail("Expected projectNotFound error, got: \(error)")
            }
        }
    }

    /// TEST 5: workingDirectoryが未設定の場合はエラー
    func testLogUploadService_NoWorkingDirectory_ThrowsError() throws {
        // workingDirectoryなしのプロジェクトを作成
        let noWdProjectId = ProjectID(value: "prj_no_wd")
        let project = Project(
            id: noWdProjectId,
            name: "No WD Project",
            workingDirectory: nil
        )
        try projectRepository.save(project)

        let service = LogUploadService(
            directoryManager: directoryManager,
            projectRepository: projectRepository,
            executionLogRepository: executionLogRepository
        )

        let logData = Data("Test log".utf8)

        XCTAssertThrowsError(
            try service.uploadLog(
                executionLogId: "exec_123",
                agentId: "agt_456",
                taskId: "task_789",
                projectId: noWdProjectId.value,
                logData: logData,
                originalFilename: "test.log"
            )
        ) { error in
            XCTAssertTrue(error is LogUploadError)
            if case LogUploadError.workingDirectoryNotConfigured = error {
                // 期待通り
            } else {
                XCTFail("Expected workingDirectoryNotConfigured error, got: \(error)")
            }
        }
    }

    /// TEST 6: ファイルサイズ超過時はエラー
    func testLogUploadService_FileTooLarge_ThrowsError() throws {
        let service = LogUploadService(
            directoryManager: directoryManager,
            projectRepository: projectRepository,
            executionLogRepository: executionLogRepository,
            maxFileSizeMB: 1  // 1MB制限
        )

        // 2MBのデータを作成
        let largeData = Data(repeating: UInt8(ascii: "x"), count: 2 * 1024 * 1024)

        XCTAssertThrowsError(
            try service.uploadLog(
                executionLogId: testExecutionLogId.value,
                agentId: testAgentId.value,
                taskId: testTaskId.value,
                projectId: testProjectId.value,
                logData: largeData,
                originalFilename: "large.log"
            )
        ) { error in
            XCTAssertTrue(error is LogUploadError)
            if case LogUploadError.fileTooLarge = error {
                // 期待通り
            } else {
                XCTFail("Expected fileTooLarge error, got: \(error)")
            }
        }
    }

    /// TEST 7: 異なるエージェントIDで異なるディレクトリに保存される
    func testLogUploadService_DifferentAgents_DifferentDirectories() throws {
        let service = LogUploadService(
            directoryManager: directoryManager,
            projectRepository: projectRepository,
            executionLogRepository: executionLogRepository
        )

        let logData = Data("Test log".utf8)

        let result1 = try service.uploadLog(
            executionLogId: testExecutionLogId.value,
            agentId: "agt_001",
            taskId: testTaskId.value,
            projectId: testProjectId.value,
            logData: logData,
            originalFilename: "test.log"
        )

        // 別のエージェントとExecutionLogを作成
        let agent2 = Agent(
            id: AgentID(value: "agt_002"),
            name: "Test Agent 2",
            role: "Developer"
        )
        try agentRepository.save(agent2)

        let execLog2 = ExecutionLog(
            id: ExecutionLogID(value: "exec_002"),
            taskId: testTaskId,
            agentId: AgentID(value: "agt_002"),
            status: .completed,
            startedAt: Date(),
            completedAt: Date(),
            exitCode: 0,
            durationSeconds: 10.0,
            logFilePath: nil,
            errorMessage: nil
        )
        try executionLogRepository.save(execLog2)

        let result2 = try service.uploadLog(
            executionLogId: "exec_002",
            agentId: "agt_002",
            taskId: testTaskId.value,
            projectId: testProjectId.value,
            logData: logData,
            originalFilename: "test.log"
        )

        XCTAssertNotEqual(result1.logFilePath, result2.logFilePath)
        XCTAssertTrue(result1.logFilePath!.contains("agt_001"))
        XCTAssertTrue(result2.logFilePath!.contains("agt_002"))
    }
}
