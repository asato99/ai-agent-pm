// UITests/PRD/PRD05_DependencyBlockingTests.swift
// PRD 05: 依存関係ブロックUIテスト
//
// ⚠️ テスト実行ルール:
// 修正対象のテストクラス/メソッドのみを実行すること
// 例: xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
//       -only-testing:AIAgentPMUITests/DependencyBlockingTests

import XCTest

// MARK: - PRD 05: Dependency Blocking Tests (依存関係ブロック)

/// 依存関係によるタスク状態遷移ブロック機能のテスト
/// 要件: TASKS.md - 依存関係の遵守（アプリで強制ブロック）
final class DependencyBlockingTests: BasicDataUITestCase {

    /// TS-DEP-001: 依存タスク未完了時はin_progressに遷移不可
    /// 要件: 先行タスクが done になるまで in_progress に移行不可
    func testBlockedWhenDependencyNotComplete() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクボードの読み込みを待つ
        Thread.sleep(forTimeInterval: 1.0)

        // 依存タスクを選択（Cmd+Shift+D）
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        app.typeKey("d", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "依存タスクの詳細が表示されること")

        // TaskDetailView内のステータスPickerを探す（識別子で検索）
        let statusPickerPredicate = NSPredicate(format: "identifier == 'StatusPicker'")
        var statusPicker = app.popUpButtons.matching(statusPickerPredicate).firstMatch

        // Pickerが見つからない場合はdescendantsで検索
        if !statusPicker.waitForExistence(timeout: 3) {
            // macOS SwiftUIではPickerがpopUpButtonsとして認識されないことがある
            // 全要素から検索
            statusPicker = app.descendants(matching: .popUpButton).matching(statusPickerPredicate).firstMatch
        }
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3), "ステータスPickerが存在すること")

        // In Progressに変更しようとする
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.5)  // メニュー表示待ち

        // メニュー項目を検索
        let inProgressOption = app.menuItems["In Progress"]
        XCTAssertTrue(inProgressOption.waitForExistence(timeout: 3), "In Progressメニュー項目が存在すること")
        inProgressOption.click()

        // エラーアラートが表示されることを確認
        Thread.sleep(forTimeInterval: 1.0)  // アラート表示待ち

        // macOS SwiftUIアラートはsheetsとして表示される
        let sheet = app.sheets.firstMatch

        // エラーアラートが表示されることを確認
        // 依存関係が未完了のタスクをIn Progressにしようとした場合、
        // UpdateTaskStatusUseCaseがDependencyNotCompleteエラーをスローする
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "依存関係ブロック時にエラーアラートが表示されること")

        // シート内のOKボタンでアラートを閉じる（TouchBarのOKボタンと区別）
        let okButton = sheet.buttons["OK"]
        if okButton.waitForExistence(timeout: 2) {
            okButton.click()
        }
    }

    /// TS-DEP-002: 依存タスク全完了時はin_progressに遷移可能
    /// 要件: 全ての依存タスクがdoneなら遷移可能
    func testAllowedWhenAllDependenciesComplete() throws {
        // このテストには先行タスクをdoneにする操作が必要
        // テストデータでは先行タスクがtodoなので、手動で完了させる必要がある
        XCTFail("依存タスク完了後の遷移テストはデータ操作が必要 - 将来実装")
        throw TestError.failedPrecondition("依存タスク完了後の遷移テストはデータ操作が必要 - 将来実装")
    }

    /// TS-DEP-003: Blockedカラムに依存待ちタスクが表示される
    /// 要件: blocked状態のタスクはBlockedカラムに表示
    func testBlockedTasksInBlockedColumn() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        Thread.sleep(forTimeInterval: 1.0)  // タスクボード読み込み待ち

        // Blockedカラムの存在確認 - カラムヘッダーで検索
        let blockedHeader = app.staticTexts["Blocked"]
        XCTAssertTrue(blockedHeader.waitForExistence(timeout: 5), "Blockedカラムヘッダーが存在すること")

        // API統合タスクが表示されていることを確認 - タイトルラベルで検索
        // タスクカードボタンのラベルに「API統合」が含まれるものを検索
        let blockedTaskPredicate = NSPredicate(format: "label CONTAINS 'API統合'")
        let blockedTask = app.buttons.matching(blockedTaskPredicate).firstMatch
        XCTAssertTrue(blockedTask.waitForExistence(timeout: 5), "BlockedタスクがBlockedカラムに表示されること")
    }

    /// TS-DEP-004: ステータス変更時にブロックエラーが表示される
    /// 要件: MCP経由の状態変更もブロック対象
    /// 注: このテストはtestBlockedWhenDependencyNotCompleteと同様のシナリオ
    func testBlockErrorDisplayedOnStatusChange() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクボードの読み込みを待つ
        Thread.sleep(forTimeInterval: 1.0)

        // 依存タスクを選択（Cmd+Shift+D）
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        app.typeKey("d", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "依存タスクの詳細が表示されること")

        // TaskDetailView内のステータスPickerを探す
        let statusPickerPredicate = NSPredicate(format: "identifier == 'StatusPicker'")
        let statusPicker = app.popUpButtons.matching(statusPickerPredicate).firstMatch

        XCTAssertTrue(statusPicker.waitForExistence(timeout: 5), "ステータスPickerが見つかること")

        // In Progressに変更しようとする
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.5)

        let inProgressOption = app.menuItems["In Progress"]
        XCTAssertTrue(inProgressOption.waitForExistence(timeout: 3), "In Progressメニュー項目が見つかること")
        inProgressOption.click()

        // エラーアラートが表示されることを確認
        Thread.sleep(forTimeInterval: 1.0)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "ステータス変更時にブロックエラーが表示されること")

        // シート内のOKボタンでアラートを閉じる
        let okButton = sheet.buttons["OK"]
        if okButton.waitForExistence(timeout: 2) {
            okButton.click()
        }
    }
}
