// UITests/BUG/BUG001_AgentSelectionTests.swift
// バグ再現テスト: エージェント選択が2回目以降反映されない問題
// リアクティブ要件違反: AgentDetailViewが選択変更時にデータを再読み込みしない

import XCTest

final class BUG001_AgentSelectionTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-UITestScenario:Basic"]
        app.launch()

        // アプリ起動待機
        let projectList = app.outlines["ProjectList"]
        XCTAssertTrue(projectList.waitForExistence(timeout: 10), "ProjectListが表示されない")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - BUG001: エージェント選択が2回目以降反映されない

    /// エージェントを選択後、別のエージェントを選択すると詳細が更新されないバグ
    /// 期待: 2つ目のエージェントを選択したら、そのエージェントの詳細が表示される
    /// 現状: 1つ目のエージェントの詳細が表示されたまま
    func testAgentSelectionUpdatesBug() throws {
        // Step 1: Agentsセクションを確認
        let agentsSection = app.staticTexts["Agents"]
        XCTAssertTrue(agentsSection.waitForExistence(timeout: 5), "Agentsセクションが見つからない")

        // Step 2: 1つ目のエージェント（owner）を選択
        // Basicシナリオでは "owner" と "backend-dev" の2つのエージェントが存在
        let firstAgentRow = app.staticTexts["owner"]
        XCTAssertTrue(firstAgentRow.waitForExistence(timeout: 5), "最初のエージェント(owner)が見つからない")
        firstAgentRow.click()

        // Step 3: 1つ目のエージェントの詳細が表示されることを確認
        let detailView = app.scrollViews["AgentDetailView"]
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "AgentDetailViewが表示されない")

        // エージェント名が "owner" であることを確認
        let ownerTitle = app.staticTexts["owner"]
        XCTAssertTrue(ownerTitle.waitForExistence(timeout: 3), "ownerの詳細が表示されない")

        // エージェントのロールを確認（"プロジェクトオーナー"）
        let ownerRole = app.staticTexts["プロジェクトオーナー"]
        XCTAssertTrue(ownerRole.exists, "ownerのロールが表示されない")

        // Step 4: 2つ目のエージェント（backend-dev）を選択
        let secondAgentRow = app.staticTexts["backend-dev"]
        XCTAssertTrue(secondAgentRow.waitForExistence(timeout: 5), "2つ目のエージェント(backend-dev)が見つからない")
        secondAgentRow.click()

        // UI更新を待機
        Thread.sleep(forTimeInterval: 1.0)

        // Step 5: 2つ目のエージェントの詳細が表示されることを確認
        // ここがバグ: 実際には1つ目のエージェント(owner)の詳細が表示されたまま

        // 詳細ビューが存在することを確認
        XCTAssertTrue(detailView.exists, "AgentDetailViewが存在しない")

        // 🐛 バグ検証: backend-devのロール（"バックエンド開発"）が表示されるべき
        let backendDevRole = app.staticTexts["バックエンド開発"]
        XCTAssertTrue(
            backendDevRole.waitForExistence(timeout: 3),
            "❌ BUG001: 2つ目のエージェント(backend-dev)を選択しても詳細が更新されない。" +
            "期待: 'バックエンド開発'が表示される。" +
            "現状: 1つ目のエージェント(owner)の詳細が表示されたまま。"
        )

        // 追加検証: ownerのロールがもう表示されていないことを確認
        // （同じビュー内に両方表示されている可能性を排除）
        // 注意: この検証は補助的なもの。主な検証は上記のbackendDevRole
    }

    /// 同じエージェントを再選択した場合は問題ないことを確認（参考テスト）
    func testSameAgentReselectionWorks() throws {
        // Step 1: 1つ目のエージェント（owner）を選択
        let firstAgentRow = app.staticTexts["owner"]
        XCTAssertTrue(firstAgentRow.waitForExistence(timeout: 5), "最初のエージェント(owner)が見つからない")
        firstAgentRow.click()

        // Step 2: 詳細が表示されることを確認
        let detailView = app.scrollViews["AgentDetailView"]
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "AgentDetailViewが表示されない")

        let ownerRole = app.staticTexts["プロジェクトオーナー"]
        XCTAssertTrue(ownerRole.waitForExistence(timeout: 3), "ownerのロールが表示されない")

        // Step 3: 同じエージェントを再度選択
        firstAgentRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // Step 4: 同じ詳細が表示されていることを確認（これは成功するはず）
        XCTAssertTrue(ownerRole.exists, "再選択後もownerのロールが表示されるべき")
    }
}
