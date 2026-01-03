// UITests/PRD/PRD01_ProjectListTests.swift
// PRD 01: プロジェクトリストUIテスト
//
// ⚠️ テスト実行ルール:
// 修正対象のテストクラス/メソッドのみを実行すること
// 例: xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
//       -only-testing:AIAgentPMUITests/ProjectListTests

import XCTest

// MARK: - PRD 01: Project List Tests

final class ProjectListTests: BasicDataUITestCase {

    /// デバッグ用: XCUITestが見ているUI階層をダンプ
    func testDebugUIHierarchy() throws {
        print("======= DEBUG: UI Hierarchy =======")
        print("App state: \(app.state.rawValue)")

        // 各種要素タイプの数をチェック
        print("Windows: \(app.windows.count)")
        print("Groups: \(app.groups.count)")
        print("SplitGroups: \(app.splitGroups.count)")
        print("ScrollViews: \(app.scrollViews.count)")
        print("Tables: \(app.tables.count)")
        print("OutlineGroups: \(app.outlines.count)")
        print("StaticTexts: \(app.staticTexts.count)")
        print("Buttons: \(app.buttons.count)")
        print("NavigationBars: \(app.navigationBars.count)")
        print("Toolbars: \(app.toolbars.count)")
        print("ToolbarButtons: \(app.toolbarButtons.count)")

        // ProjectList識別子を直接検索
        let projectList = app.descendants(matching: .any).matching(identifier: "ProjectList").firstMatch
        print("ProjectList exists: \(projectList.exists)")

        // NewProjectButtonを様々な方法で検索
        print("--- NewProjectButton search ---")
        let btnAsButton = app.buttons["NewProjectButton"]
        print("buttons['NewProjectButton']: \(btnAsButton.exists)")
        let btnAsToolbar = app.toolbarButtons["NewProjectButton"]
        print("toolbarButtons['NewProjectButton']: \(btnAsToolbar.exists)")
        let btnAsAny = app.descendants(matching: .any)["NewProjectButton"]
        print("descendants(any)['NewProjectButton']: \(btnAsAny.exists)")

        // ツールバー内のボタンを列挙
        print("--- Toolbar buttons ---")
        for toolbar in app.toolbars.allElementsBoundByIndex {
            print("Toolbar: \(toolbar.identifier)")
            for button in toolbar.buttons.allElementsBoundByIndex {
                print("  Button: '\(button.identifier)' label: '\(button.label)'")
            }
        }

        // 全ボタンを列挙
        print("--- All Buttons ---")
        for button in app.buttons.allElementsBoundByIndex.prefix(20) {
            print("  Button: id='\(button.identifier)' label='\(button.label)' title='\(button.title)'")
        }

        // "New Project" ラベルでボタンを検索
        print("--- New Project label search ---")
        let newProjByLabel = app.buttons["New Project"]
        print("buttons['New Project']: \(newProjByLabel.exists)")
        // allElementsBoundByIndexで検索してクラッシュを回避
        let projectButtons = app.buttons.allElementsBoundByIndex.filter { $0.label.lowercased().contains("project") || $0.label.lowercased().contains("new") }
        print("buttons containing 'project' or 'new': count=\(projectButtons.count)")
        for btn in projectButtons {
            print("  Found: id='\(btn.identifier)' label='\(btn.label)'"
            )
        }

        // 全ての要素をダンプ（識別子があるもの）
        print("--- Elements with identifiers ---")
        for element in app.descendants(matching: .any).allElementsBoundByIndex.prefix(100) {
            if !element.identifier.isEmpty {
                print("  \(element.elementType.rawValue): '\(element.identifier)'")
            }
        }

        print("======= END DEBUG =======")
        XCTAssertTrue(true)
    }

    /// TS-01-001: サイドバー存在確認
    /// 期待結果: プロジェクトリストが表示される
    func testProjectListSidebarExists() throws {
        // プロジェクトリストが表示されること（ナビゲーションタイトル）
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "メインウィンドウが存在すること")

        // ProjectList識別子を持つリストを確認
        let projectList = app.descendants(matching: .any).matching(identifier: "ProjectList").firstMatch
        XCTAssertTrue(projectList.waitForExistence(timeout: 5), "プロジェクトリストが存在すること")
    }

    /// TS-01-002: ツールバーボタン存在確認
    /// 期待結果: 新規作成ボタン（+）が存在する
    /// 注意: macOS SwiftUIのツールバーボタンはXCUITestに公開されないため、
    ///       キーボードショートカット(⌘N)で機能をテストする
    func testToolbarButtonsExist() throws {
        // キーボードショートカットで新規プロジェクトシートを開く
        app.typeKey("n", modifierFlags: [.command])

        // シートが表示されることで、ボタン機能が動作することを確認
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "新規プロジェクト作成ショートカット(⌘N)が動作すること")
    }

    /// TS-01-003: 新規プロジェクト作成シート表示
    /// 期待結果: シートが表示される
    func testNewProjectButtonOpensSheet() throws {
        // キーボードショートカットで新規プロジェクトシートを開く
        // (macOS SwiftUIのツールバーボタンはXCUITestに公開されない)
        app.typeKey("n", modifierFlags: [.command])

        // シートが表示される
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "新規プロジェクト作成シートが表示されること")
    }

    /// TS-01-005: プロジェクト選択によるコンテンツ変更
    /// 期待結果: プロジェクト選択でタスクボードが表示される
    func testProjectSelectionChangesContent() throws {
        // プロジェクトリストの存在確認
        let projectList = app.descendants(matching: .any).matching(identifier: "ProjectList").firstMatch
        XCTAssertTrue(projectList.waitForExistence(timeout: 5), "プロジェクトリストが存在すること")

        // プロジェクト行を探す（テストプロジェクト）
        let projectRow = app.staticTexts["テストプロジェクト"]
        if projectRow.waitForExistence(timeout: 5) {
            projectRow.click()

            // タスクボードが表示される（Backlogカラムヘッダー）
            let backlogHeader = app.staticTexts["Backlog"]
            XCTAssertTrue(backlogHeader.waitForExistence(timeout: 5), "タスクボードが表示されること")
        } else {
            XCTFail("テストプロジェクトが存在しません")
        }
    }

    /// TS-01-006: プロジェクトカード情報表示
    func testProjectCardInfo() throws {
        // プロジェクトリストにプロジェクト名が表示される
        let projectName = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectName.waitForExistence(timeout: 5), "プロジェクト名が表示されること")
    }

    /// TS-01-007: コンテキストメニュー表示（未実装のため保留）
    func testContextMenuDisplay() throws {
        // 現在のUIにはコンテキストメニューが未実装のためスキップ
        // 将来的に実装後にテストを有効化
        XCTFail("コンテキストメニューは未実装")
        throw TestError.failedPrecondition("コンテキストメニューは未実装")
    }

    /// TS-01-008: ソートオプション（未実装のため保留）
    func testSortOptions() throws {
        XCTFail("ソートオプションは未実装")
        throw TestError.failedPrecondition("ソートオプションは未実装")
    }

    /// TS-01-009: フィルターオプション（未実装のため保留）
    func testFilterOptions() throws {
        XCTFail("フィルターオプションは未実装")
        throw TestError.failedPrecondition("フィルターオプションは未実装")
    }
}

// MARK: - PRD 01: Empty State Tests (空状態専用)

/// TS-01-004: 空状態表示テスト
/// 空状態（プロジェクトなし）でのUI確認
final class ProjectListEmptyStateTests: EmptyStateUITestCase {

    /// TS-01-004: 空状態表示
    /// 期待結果: 「プロジェクトがありません」と新規作成ボタンが表示される
    func testEmptyStateWhenNoProjects() throws {
        // 空状態メッセージ
        let emptyMessage = app.staticTexts["プロジェクトがありません"]
        XCTAssertTrue(emptyMessage.waitForExistence(timeout: 5), "「プロジェクトがありません」が表示されること")

        // 新規作成を促すボタン（ボタンのラベルテキストで検索）
        // SwiftUIのoverlay内ボタンは識別子が公開されない場合があるため、ラベルで検索
        let createProjectButton = app.buttons["新規プロジェクト作成"]
        XCTAssertTrue(createProjectButton.waitForExistence(timeout: 5), "新規作成を促すボタンが表示されること")
    }
}

// MARK: - Additional Project List Tests

/// プロジェクト一覧の追加テスト
/// 要件: PROJECTS.md - プロジェクト管理機能の拡張
final class ProjectListExtendedTests: BasicDataUITestCase {

    /// TS-01-010: プロジェクト作成フォームに説明フィールドがある
    /// 要件: プロジェクトの説明を入力可能
    func testProjectFormHasDescriptionField() throws {
        // キーボードショートカットで新規プロジェクトシートを開く
        app.typeKey("n", modifierFlags: [.command])

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "新規プロジェクトシートが表示されること")

        // 説明フィールドの存在確認
        // 実装状況により識別子またはラベルで検索
        let descriptionLabel = app.staticTexts["Description"]
        let descriptionField = app.textFields["Description"]
        let textEditor = app.textViews.firstMatch

        XCTAssertTrue(descriptionLabel.exists || descriptionField.exists || textEditor.exists,
                      "説明フィールドが存在すること")
    }

    /// TS-01-011: プロジェクト詳細でエージェント割り当てUIがある
    /// 要件: プロジェクトへのエージェント割り当て機能
    func testProjectAgentAssignmentUI() throws {
        // プロジェクトへのエージェント割り当てUIは未実装
        // 実装後: プロジェクト詳細にエージェント割り当てセクションが存在することを確認
        XCTFail("プロジェクトへのエージェント割り当てUIは未実装")
        throw TestError.failedPrecondition("プロジェクトへのエージェント割り当てUIは未実装")
    }
}
