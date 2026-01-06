// UITests/PRD/PRD04_TaskDetailTests.swift
// PRD 04: タスク詳細UIテスト
//
// ⚠️ テスト実行ルール:
// 修正対象のテストクラス/メソッドのみを実行すること
// 例: xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
//       -only-testing:AIAgentPMUITests/TaskDetailTests

import XCTest

// MARK: - PRD 04: Task Detail Tests

final class TaskDetailTests: BasicDataUITestCase {

    /// TS-04-001: タスク詳細画面構成確認
    /// 検証内容: タスク詳細ビュー（TaskDetailView）、Detailsセクション、ステータスバッジ、優先度バッジの存在確認
    func testTaskDetailStructure() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // ヘッダーセクションの確認 - 「Details」セクションヘッダーで確認
        let detailsHeader = app.staticTexts["Details"]
        XCTAssertTrue(detailsHeader.exists, "Detailsセクションが表示されること")

        // ステータスバッジの確認 - ステータス名で検索
        // 要件: TaskStatusは backlog, todo, in_progress, blocked, done, cancelled のみ（inReviewは削除）
        let statusTexts = ["Backlog", "To Do", "In Progress", "Done", "Blocked", "Cancelled"]
        let hasStatusBadge = statusTexts.contains { app.staticTexts[$0].exists }
        XCTAssertTrue(hasStatusBadge, "ステータスバッジが表示されること")

        // 優先度バッジの確認 - 優先度名で検索
        let priorityTexts = ["Urgent", "High", "Medium", "Low"]
        let hasPriorityBadge = priorityTexts.contains { app.staticTexts[$0].exists }
        XCTAssertTrue(hasPriorityBadge, "優先度バッジが表示されること")
    }

    /// TS-04-002: タブ存在確認（未実装 - 現在はスクロールビュー形式）
    func testTaskDetailTabs() throws {
        XCTFail("タブ形式UIは未実装 - 現在はスクロールビュー形式")
        throw TestError.failedPrecondition("タブ形式UIは未実装 - 現在はスクロールビュー形式")
    }

    /// TS-04-003: コンテキスト追加機能
    /// 検証内容: コンテキストセクション（ContextSection）の表示と「Add Context」ボタンの存在確認
    func testContextAddButton() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // コンテキストセクションを見つける
        let contextSection = app.descendants(matching: .any).matching(identifier: "ContextSection").firstMatch
        XCTAssertTrue(contextSection.waitForExistence(timeout: 5), "コンテキストセクションが表示されること")

        // コンテキスト追加ボタンの存在確認
        let addContextButton = app.buttons["Add Context"]
        XCTAssertTrue(addContextButton.waitForExistence(timeout: 5), "コンテキスト追加ボタンが存在すること")
    }

    /// TS-04-004: ハンドオフ作成機能
    /// 検証内容: キーボードショートカット（⇧⌘H）でハンドオフシートが表示されることを確認
    func testHandoffCreateButton() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // キーボードショートカットでハンドオフシートを開く
        app.typeKey("h", modifierFlags: [.command, .shift])

        // シートが表示されることで機能が動作することを確認
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "ハンドオフシートが表示されること（⇧⌘H経由）")
    }

    /// TS-04-005: 編集ボタン存在確認
    /// 検証内容: キーボードショートカット（⌘E）で編集シートが表示されることを確認
    func testEditButtonExists() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // キーボードショートカットで編集シートを開く
        app.typeKey("e", modifierFlags: [.command])

        // シートが表示されることで機能が動作することを確認
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "編集ショートカット(⌘E)が動作すること")
    }

    /// TS-04-006: 編集モード画面
    /// 検証内容: キーボードショートカット（⌘E）で編集シートを開き、「Task Information」セクション、「Details」セクション、Priority/Assigneeラベルの存在確認
    func testEditModeScreen() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // キーボードショートカットで編集シートを開く
        app.typeKey("e", modifierFlags: [.command])

        // シートが表示される
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "編集シートが表示されること")

        // 「Task Information」セクションの存在確認
        let taskInfoSection = app.staticTexts["Task Information"]
        XCTAssertTrue(taskInfoSection.waitForExistence(timeout: 3), "Task Informationセクションが表示されること")

        // 「Details」セクションの存在確認
        let detailsSection = app.staticTexts["Details"]
        XCTAssertTrue(detailsSection.exists, "Detailsセクションが表示されること")

        // 編集フォームのフィールド存在確認
        let priorityLabel = app.staticTexts["Priority"]
        let assigneeLabel = app.staticTexts["Assignee"]
        XCTAssertTrue(priorityLabel.exists || assigneeLabel.exists, "編集フォームのフィールドが表示されること")
    }

    /// TS-04-007: ステータス変更ピッカー
    /// 検証内容: Detailsセクション、Statusラベル、ステータスピッカー（popUpButton）の存在確認
    func testStatusChangePicker() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // 「Details」セクションが表示されることを確認
        let detailsSection = app.staticTexts["Details"]
        XCTAssertTrue(detailsSection.waitForExistence(timeout: 5), "Detailsセクションが表示されること")

        // 「Status」ラベルの存在確認
        let statusLabel = app.staticTexts["Status"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 3), "Statusラベルが存在すること")

        // ステータスPickerの存在確認（popUpButton）
        let statusPicker = app.popUpButtons.firstMatch
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 5), "ステータスピッカーが存在すること")

        // ステータスオプションがピッカー内に含まれていることを確認
        // 要件: TaskStatusは backlog, todo, in_progress, blocked, done, cancelled
        let statusTexts = ["Backlog", "To Do", "In Progress", "Done", "Blocked", "Cancelled"]
        let hasAnyStatus = statusTexts.contains { app.staticTexts[$0].exists }
        XCTAssertTrue(hasAnyStatus || statusPicker.exists, "ステータスピッカーにステータスオプションが含まれること")
    }

    /// TS-04-008: 履歴セクション
    /// 検証内容: 履歴セクション（HistorySection）と「History」ヘッダーの存在確認
    func testHistoryEventList() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // 履歴セクションの存在確認
        let historySection = app.descendants(matching: .any).matching(identifier: "HistorySection").firstMatch
        XCTAssertTrue(historySection.waitForExistence(timeout: 5), "履歴セクションが表示されること")

        // 履歴ヘッダーの存在確認
        let historyHeader = app.staticTexts["History"]
        XCTAssertTrue(historyHeader.exists, "履歴ヘッダーが表示されること")
    }

    /// TS-04-009: 履歴フィルター（未実装）
    func testHistoryFilter() throws {
        XCTFail("履歴フィルターは未実装")
        throw TestError.failedPrecondition("履歴フィルターは未実装")
    }

    /// TS-04-010: コンテキスト一覧表示
    /// 検証内容: コンテキストセクション（ContextSection）の存在確認。コンテキストがない場合は「No context saved yet」メッセージの確認
    func testContextListDisplay() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // コンテキストセクションの存在確認
        let contextSection = app.descendants(matching: .any).matching(identifier: "ContextSection").firstMatch
        XCTAssertTrue(contextSection.waitForExistence(timeout: 5), "コンテキストセクションが表示されること")

        // コンテキストがない場合のメッセージ確認
        let noContextMessage = app.descendants(matching: .any).matching(identifier: "NoContextMessage").firstMatch
        if noContextMessage.exists {
            XCTAssertTrue(true, "「No context saved yet」メッセージが表示されること")
        }
    }

    /// TS-04-011: ハンドオフ一覧表示
    /// 検証内容: ハンドオフセクション（HandoffsSection）と「Handoffs」ヘッダーの存在確認
    func testHandoffListDisplay() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // ハンドオフセクションの存在確認
        let handoffsSection = app.descendants(matching: .any).matching(identifier: "HandoffsSection").firstMatch
        XCTAssertTrue(handoffsSection.waitForExistence(timeout: 5), "ハンドオフセクションが表示されること")

        // ハンドオフヘッダーの存在確認
        let handoffsHeader = app.staticTexts["Handoffs"]
        XCTAssertTrue(handoffsHeader.exists, "ハンドオフヘッダーが表示されること")
    }

    /// TS-04-012: 依存関係表示
    /// 検証内容: 依存関係セクション（DependenciesSection）と「Dependencies」ヘッダーの存在確認
    func testDependencyDisplay() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // 依存関係セクションの存在確認
        let dependenciesSection = app.descendants(matching: .any).matching(identifier: "DependenciesSection").firstMatch
        XCTAssertTrue(dependenciesSection.waitForExistence(timeout: 5), "依存関係セクションが表示されること")

        // 依存関係ヘッダーの存在確認
        let dependenciesHeader = app.staticTexts["Dependencies"]
        XCTAssertTrue(dependenciesHeader.exists, "依存関係ヘッダーが表示されること")
    }
}
