// UITests/PRD/PRD06_ResourceBlockingTests.swift
// PRD 06: リソース可用性ブロックUIテスト
//
// ⚠️ テスト実行ルール:
// 修正対象のテストクラス/メソッドのみを実行すること
// 例: xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
//       -only-testing:AIAgentPMUITests/ResourceBlockingTests

import XCTest

// MARK: - PRD 06: Resource Blocking Tests (リソース可用性ブロック)

/// エージェントの並列実行可能数によるブロック機能のテスト
/// 要件: AGENTS.md / TASKS.md - リソース可用性の遵守
final class ResourceBlockingTests: BasicDataUITestCase {

    /// ヘルパー: プロジェクトを選択してタスクボードを表示
    private func selectProject() throws {
        let projectRow = app.staticTexts["テストプロジェクト"]
        if projectRow.waitForExistence(timeout: 5) {
            projectRow.click()
        } else {
            XCTFail("テストプロジェクトが存在しません")
            throw TestError.failedPrecondition("テストプロジェクトが存在しません")
        }
    }

    /// ヘルパー: 指定タイトルのタスクを選択して詳細を開く
    /// 戦略: UIテスト用キーボードショートカットを使用
    /// - 追加開発タスク: Cmd+Shift+G
    private func openTaskDetail(title: String) throws {
        try selectProject()
        Thread.sleep(forTimeInterval: 1.0)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch

        if title.contains("追加開発タスク") {
            // Cmd+Shift+G でリソーステストタスクを選択
            app.typeKey("g", modifierFlags: [.command, .shift])
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertTrue(detailView.waitForExistence(timeout: 5), "リソーステストタスクの詳細が表示されること")
        } else {
            XCTFail("タスク「\(title)」用のショートカットが定義されていません")
            throw TestError.failedPrecondition("タスク「\(title)」用のショートカットが定義されていません")
        }
    }

    /// TS-RES-001: 並列上限到達時は新規in_progress不可
    /// 要件: アサイン先エージェントの並列実行可能数を超える場合、in_progress に移行不可
    func testBlockedWhenMaxParallelReached() throws {
        // 追加開発タスクを選択（backend-devにアサイン済み、devAgentはすでにAPI実装がin_progress）
        try openTaskDetail(title: "追加開発タスク")

        // TaskDetailView内のステータスPickerを探す
        let statusPickerPredicate = NSPredicate(format: "identifier == 'StatusPicker'")
        let statusPicker = app.popUpButtons.matching(statusPickerPredicate).firstMatch
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 5), "ステータスPickerが存在すること")

        // In Progressに変更しようとする
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.5)

        let inProgressOption = app.menuItems["In Progress"]
        XCTAssertTrue(inProgressOption.waitForExistence(timeout: 3), "In Progressメニュー項目が存在すること")
        inProgressOption.click()

        // エラーアラートが表示されることを確認
        Thread.sleep(forTimeInterval: 1.0)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "リソースブロック時にエラーアラートが表示されること")

        // シート内のOKボタンでアラートを閉じる
        let okButton = sheet.buttons["OK"]
        if okButton.waitForExistence(timeout: 2) {
            okButton.click()
        }
    }

    /// TS-RES-002: 並列上限未満時はin_progress可能
    /// 要件: 並列数がmaxParallelTasks未満なら遷移可能
    func testAllowedWhenBelowMaxParallel() throws {
        // ownerエージェントは現在in_progressタスクがないので、
        // ownerにアサインされたタスクをin_progressにできるはず
        // テストデータにはownerにアサインされたtodoタスクがないため失敗
        XCTFail("ownerにアサインされたtodoタスクがテストデータにないため - 将来追加")
        throw TestError.failedPrecondition("ownerにアサインされたtodoタスクがテストデータにないため - 将来追加")
    }

    /// TS-RES-003: エージェント詳細に現在の並列数が表示される
    /// 要件: エージェントの現在のin_progressタスク数を表示
    func testAgentDetailShowsCurrentParallelCount() throws {
        // データ読み込み待ち
        Thread.sleep(forTimeInterval: 2.0)

        // エージェント名で検索
        let devAgent = app.staticTexts["backend-dev"]
        XCTAssertTrue(devAgent.waitForExistence(timeout: 10), "エージェントが存在すること")

        devAgent.click()

        // AgentDetailView識別子で詳細パネルを確認
        let detailView = app.descendants(matching: .any).matching(identifier: "AgentDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "AgentDetailViewが表示されること")

        // 現在の並列数表示は未実装
        // 実装後: "In Progress: 1 / 1" のような表示を確認
        XCTFail("エージェント詳細の現在並列数表示は未実装 - UI追加が必要")
        throw TestError.failedPrecondition("エージェント詳細の現在並列数表示は未実装 - UI追加が必要")
    }

    /// TS-RES-004: ステータス変更時にリソースエラーが表示される
    /// 要件: 並列上限到達時にエラーメッセージを表示
    /// 注: このテストはtestBlockedWhenMaxParallelReachedと同様のシナリオ
    func testResourceErrorDisplayedOnStatusChange() throws {
        // 追加開発タスクを選択してステータス変更を試みる
        try openTaskDetail(title: "追加開発タスク")

        // TaskDetailView内のステータスPickerを探す
        let statusPickerPredicate = NSPredicate(format: "identifier == 'StatusPicker'")
        let statusPicker = app.popUpButtons.matching(statusPickerPredicate).firstMatch
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 5), "ステータスPickerが存在すること")

        // In Progressに変更しようとする
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.5)

        let inProgressOption = app.menuItems["In Progress"]
        XCTAssertTrue(inProgressOption.waitForExistence(timeout: 3), "In Progressメニュー項目が存在すること")
        inProgressOption.click()

        // エラーアラートが表示されることを確認
        Thread.sleep(forTimeInterval: 1.0)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "ステータス変更時にリソースエラーが表示されること")

        // シート内のOKボタンでアラートを閉じる
        let okButton = sheet.buttons["OK"]
        if okButton.waitForExistence(timeout: 2) {
            okButton.click()
        }
    }
}
