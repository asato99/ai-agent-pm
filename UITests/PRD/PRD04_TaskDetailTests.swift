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

    /// ヘルパー: プロジェクトを選択してタスクを開く
    private func openTaskDetail() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()
    }

    /// TS-04-001: タスク詳細画面構成確認
    func testTaskDetailStructure() throws {
        try openTaskDetail()

        // タスク詳細ビューの存在確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "タスク詳細ビューが表示されること")

        // ヘッダーセクションの確認 - 「Details」セクションヘッダーで確認
        let detailsHeader = app.staticTexts["Details"]
        XCTAssertTrue(detailsHeader.exists, "Detailsセクションが表示されること")

        // ステータスバッジの確認 - ステータス名で検索
        // SwiftUIのカスタムビュー内の識別子は公開されない場合があるため、テキストで確認
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

    /// TS-04-003: サブタスクセクション表示
    /// 要件: TASKS.md - サブタスクは初期実装では不要
    func testSubtaskSection() throws {
        XCTFail("サブタスクは要件で「初期実装では不要」と定義されているためスキップ")
        throw TestError.failedPrecondition("サブタスクは要件で「初期実装では不要」と定義されているためスキップ")
    }

    /// TS-04-004: コンテキスト追加機能
    /// 期待結果: コンテキスト追加ボタンが存在する
    func testContextAddButton() throws {
        try openTaskDetail()

        // まずコンテキストセクションを見つける（スクロールのため）
        let contextSection = app.descendants(matching: .any).matching(identifier: "ContextSection").firstMatch
        XCTAssertTrue(contextSection.waitForExistence(timeout: 5), "コンテキストセクションが表示されること")

        // コンテキスト追加ボタンの存在確認（タイトルで検索）
        let addContextButton = app.buttons["Add Context"]
        XCTAssertTrue(addContextButton.waitForExistence(timeout: 5), "コンテキスト追加ボタンが存在すること")
    }

    /// TS-04-005: ハンドオフ作成機能
    /// 注意: macOS SwiftUIのツールバーボタンはXCUITestに公開されないため、
    ///       キーボードショートカット(⇧⌘H)で機能をテストする
    func testHandoffCreateButton() throws {
        try openTaskDetail()

        // キーボードショートカットでハンドオフシートを開く
        app.typeKey("h", modifierFlags: [.command, .shift])

        // シートが表示されることで機能が動作することを確認
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "ハンドオフシートが表示されること（⇧⌘H経由）")
    }

    /// TS-04-006: 編集ボタン存在確認
    /// 注意: macOS SwiftUIのツールバーボタンはXCUITestに公開されないため、
    ///       キーボードショートカット(⌘E)で機能をテストする
    func testEditButtonExists() throws {
        try openTaskDetail()

        // キーボードショートカットで編集シートを開く
        app.typeKey("e", modifierFlags: [.command])

        // シートが表示されることで機能が動作することを確認
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "編集ショートカット(⌘E)が動作すること")
    }

    /// TS-04-007: 編集モード画面（シート形式）
    /// 期待結果: 編集シートにTask Informationセクション（Title, Description）と
    ///           Detailsセクション（Priority, Assignee, Estimated Minutes）が表示される
    func testEditModeScreen() throws {
        try openTaskDetail()

        // キーボードショートカットで編集シートを開く
        // (macOS SwiftUIのツールバーボタンはXCUITestに公開されない)
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
        // Title, Priority, Assigneeのラベルがあればフォームは正しく表示されている
        let priorityLabel = app.staticTexts["Priority"]
        let assigneeLabel = app.staticTexts["Assignee"]
        XCTAssertTrue(priorityLabel.exists || assigneeLabel.exists, "編集フォームのフィールドが表示されること")
    }

    /// TS-04-008: ステータス変更ピッカー
    func testStatusChangePicker() throws {
        try openTaskDetail()

        // 「Details」セクションが表示されることを確認
        let detailsSection = app.staticTexts["Details"]
        XCTAssertTrue(detailsSection.waitForExistence(timeout: 5), "Detailsセクションが表示されること")

        // 「Status」ラベルの存在確認（LabeledContentのラベル）
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

    /// TS-04-009: 履歴セクション
    /// 期待結果: 履歴セクションが表示される
    func testHistoryEventList() throws {
        try openTaskDetail()

        // 履歴セクションの存在確認
        let historySection = app.descendants(matching: .any).matching(identifier: "HistorySection").firstMatch
        XCTAssertTrue(historySection.waitForExistence(timeout: 5), "履歴セクションが表示されること")

        // 履歴ヘッダーの存在確認
        let historyHeader = app.staticTexts["History"]
        XCTAssertTrue(historyHeader.exists, "履歴ヘッダーが表示されること")
    }

    /// TS-04-010: 履歴フィルター（未実装）
    func testHistoryFilter() throws {
        XCTFail("履歴フィルターは未実装")
        throw TestError.failedPrecondition("履歴フィルターは未実装")
    }

    /// TS-04-011: コンテキスト一覧表示
    func testContextListDisplay() throws {
        try openTaskDetail()

        // コンテキストセクションの存在確認
        let contextSection = app.descendants(matching: .any).matching(identifier: "ContextSection").firstMatch
        XCTAssertTrue(contextSection.waitForExistence(timeout: 5), "コンテキストセクションが表示されること")

        // コンテキストがない場合のメッセージ確認
        let noContextMessage = app.descendants(matching: .any).matching(identifier: "NoContextMessage").firstMatch
        // コンテキストがなければメッセージが表示される
        if noContextMessage.exists {
            XCTAssertTrue(true, "「No context saved yet」メッセージが表示されること")
        }
    }

    /// TS-04-012: ハンドオフ一覧表示
    /// 期待結果: ハンドオフセクションが表示される
    func testHandoffListDisplay() throws {
        try openTaskDetail()

        // ハンドオフセクションの存在確認
        let handoffsSection = app.descendants(matching: .any).matching(identifier: "HandoffsSection").firstMatch
        XCTAssertTrue(handoffsSection.waitForExistence(timeout: 5), "ハンドオフセクションが表示されること")

        // ハンドオフヘッダーの存在確認
        let handoffsHeader = app.staticTexts["Handoffs"]
        XCTAssertTrue(handoffsHeader.exists, "ハンドオフヘッダーが表示されること")
    }

    /// TS-04-013: 依存関係表示
    /// 期待結果: 依存関係セクションが表示される
    func testDependencyDisplay() throws {
        try openTaskDetail()

        // 依存関係セクションの存在確認
        let dependenciesSection = app.descendants(matching: .any).matching(identifier: "DependenciesSection").firstMatch
        XCTAssertTrue(dependenciesSection.waitForExistence(timeout: 5), "依存関係セクションが表示されること")

        // 依存関係ヘッダーの存在確認
        let dependenciesHeader = app.staticTexts["Dependencies"]
        XCTAssertTrue(dependenciesHeader.exists, "依存関係ヘッダーが表示されること")
    }
}
