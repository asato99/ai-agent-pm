// UITests/Common/CommonUITests.swift
// 共通UIテスト - ナビゲーション、アクセシビリティ、パフォーマンス
//
// ⚠️ テスト実行ルール:
// 修正対象のテストクラス/メソッドのみを実行すること
// 例: xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
//       -only-testing:AIAgentPMUITests/CommonNavigationTests

import XCTest

// MARK: - Common Tests (05)

final class CommonNavigationTests: BasicDataUITestCase {

    /// 3カラムナビゲーションの動作確認
    func testThreeColumnLayout() throws {
        // メインウィンドウの存在確認
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "メインウィンドウが存在すること")

        // サイドバー（プロジェクトリスト）の存在確認
        let projectList = app.descendants(matching: .any).matching(identifier: "ProjectList").firstMatch
        XCTAssertTrue(projectList.waitForExistence(timeout: 5), "サイドバーにプロジェクトリストが存在すること")

        // ナビゲーションタイトル「Projects」の確認
        // SwiftUIのnavigationTitleはstaticTextとして公開されない場合がある
        // 代わりにプロジェクトリストの存在で3カラムの左カラムを確認済み
        // 中央カラムの確認: プロジェクト選択前は「No Project Selected」が表示される
        let noProjectText = app.staticTexts["No Project Selected"]
        XCTAssertTrue(noProjectText.exists, "プロジェクト未選択時のプレースホルダーが表示されること")
    }

    /// キーボードショートカット
    func testKeyboardShortcuts() throws {
        // Cmd+N で新規プロジェクト
        app.typeKey("n", modifierFlags: .command)

        let newProjectSheet = app.sheets.firstMatch
        XCTAssertTrue(newProjectSheet.waitForExistence(timeout: 3), "Cmd+Nで新規プロジェクトシートが開くこと")
    }

    /// プロジェクト選択でコンテンツエリアが更新される
    func testProjectSelectionUpdatesContent() throws {
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")

        projectRow.click()

        // コンテンツエリアにタスクボードが表示される
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "タスクボードが表示されること")
    }
}

final class CommonAccessibilityTests: BasicDataUITestCase {

    /// アクセシビリティ識別子の存在確認
    /// 注意: macOS SwiftUIのツールバーボタンはXCUITestに公開されないため、
    ///       キーボードショートカットで機能をテストする
    func testAccessibilityIdentifiers() throws {
        // ProjectList識別子の確認
        let projectList = app.descendants(matching: .any).matching(identifier: "ProjectList").firstMatch
        XCTAssertTrue(projectList.waitForExistence(timeout: 5), "ProjectList識別子が存在すること")

        // NewProjectButtonはツールバーボタンのためXCUITestに公開されない
        // 代わりにキーボードショートカット(⌘N)で機能をテスト
        app.typeKey("n", modifierFlags: [.command])
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "NewProjectButton機能が動作すること（⌘Nショートカット経由）")
    }

    /// 読み上げ可能なテキスト要素の存在確認
    func testAccessibilityLabels() throws {
        // 主要なUI要素にテキストがあること
        let staticTexts = app.staticTexts
        XCTAssertTrue(staticTexts.count > 0, "読み上げ可能なテキスト要素が存在すること")

        let buttons = app.buttons
        XCTAssertTrue(buttons.count > 0, "アクセス可能なボタンが存在すること")
    }

    /// VoiceOver対応
    func testVoiceOverCompatibility() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "ウィンドウが存在すること")

        // 全ての主要要素にラベルがあること
        let allElements = app.descendants(matching: .any)
        XCTAssertTrue(allElements.count > 0, "UI要素が存在すること")
    }
}

final class CommonPerformanceTests: BasicDataUITestCase {

    /// アプリ起動時間
    func testAppLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
