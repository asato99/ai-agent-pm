// Tests/InfrastructureTests/AppSettingsRepositoryTests.swift
// アプリケーション設定リポジトリ - Infrastructure層テスト

import XCTest
import GRDB
@testable import Domain
@testable import Infrastructure

final class AppSettingsRepositoryTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var repository: AppSettingsRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_app_settings_\(UUID().uuidString).db").path
        dbQueue = try DatabaseSetup.createDatabase(at: dbPath)
        repository = AppSettingsRepository(database: dbQueue)
    }

    override func tearDownWithError() throws {
        repository = nil
        dbQueue = nil
        try super.tearDownWithError()
    }

    // MARK: - Basic Tests

    func testGetCreatesDefaultSettings() throws {
        let settings = try repository.get()

        XCTAssertEqual(settings.id, AppSettings.singletonId)
        XCTAssertNil(settings.coordinatorToken)
        XCTAssertEqual(settings.pendingPurposeTTLSeconds, AppSettings.defaultPendingPurposeTTLSeconds)
        XCTAssertFalse(settings.allowRemoteAccess)
    }

    func testSaveAndGet() throws {
        var settings = try repository.get()
        let newSettings = settings.regenerateCoordinatorToken()

        try repository.save(newSettings)

        let retrieved = try repository.get()
        XCTAssertNotNil(retrieved.coordinatorToken)
        XCTAssertEqual(retrieved.coordinatorToken, newSettings.coordinatorToken)
    }

    // MARK: - Agent Base Prompt Tests

    func testAgentBasePromptDefaultsToNil() throws {
        let settings = try repository.get()

        XCTAssertNil(settings.agentBasePrompt)
    }

    func testSaveAndGetAgentBasePrompt() throws {
        let testPrompt = """
        You are an AI Agent Instance.

        ## Working Directory
        Your working directory is: {working_dir}

        ## Workflow
        1. Call get_next_action
        2. Execute the instruction
        3. Repeat
        """

        var settings = try repository.get()
        settings = settings.withAgentBasePrompt(testPrompt)

        try repository.save(settings)

        let retrieved = try repository.get()
        XCTAssertEqual(retrieved.agentBasePrompt, testPrompt)
    }

    func testClearAgentBasePrompt() throws {
        // まずプロンプトを設定
        var settings = try repository.get()
        settings = settings.withAgentBasePrompt("Test prompt")
        try repository.save(settings)

        // プロンプトをクリア
        settings = try repository.get()
        settings = settings.withAgentBasePrompt(nil)
        try repository.save(settings)

        let retrieved = try repository.get()
        XCTAssertNil(retrieved.agentBasePrompt)
    }
}
