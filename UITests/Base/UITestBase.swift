// UITests/Base/UITestBase.swift
// UIテスト共通基盤 - ベースクラスとユーティリティ
//
// 参照: docs/test/README.md または CLAUDE.md

import XCTest

/// テスト失敗時にthrowするエラー
enum TestError: Error {
    case failedPrecondition(String)
}

// MARK: - Test Scenarios

/// テストシナリオの種類
enum UITestScenario: String {
    case empty = "Empty"           // 空状態（プロジェクトなし）
    case basic = "Basic"           // 基本データ（プロジェクト+エージェント+タスク）
    case multiProject = "MultiProject"  // 複数プロジェクト
    case internalAudit = "InternalAudit" // Internal Audit機能テスト用
}

// MARK: - Base Test Class

class AIAgentPMUITestCase: XCTestCase {

    var app: XCUIApplication!

    /// テストシナリオ（サブクラスでオーバーライド可能）
    var testScenario: UITestScenario {
        return .basic  // デフォルトは基本データ
    }

    override func setUpWithError() throws {
        continueAfterFailure = false

        // アプリを起動（デフォルトのバンドルIDを使用）
        app = XCUIApplication()

        // UIテスト用DBとシナリオを設定
        app.launchArguments = [
            "-UITesting",
            "-UITestScenario:\(testScenario.rawValue)",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]

        // アクセシビリティを有効化
        app.launchEnvironment = [
            "XCUI_ENABLE_ACCESSIBILITY": "1"
        ]

        // アプリを起動
        app.launch()

        // アプリの起動完了を待つ（waitForExistenceを使用）
        let window = app.windows.firstMatch
        if window.waitForExistence(timeout: 10) {
            // ウィンドウが見つかった場合、データシードの完了を待つ
            Thread.sleep(forTimeInterval: 2.0)
        } else {
            // ウィンドウが見つからない場合でも続行（テスト側で適切にハンドリング）
            Thread.sleep(forTimeInterval: 3.0)
            app.activate()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }
}

/// 空状態テスト用ベースクラス
class EmptyStateUITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .empty }
}

/// 基本データテスト用ベースクラス
class BasicDataUITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .basic }
}

/// 複数プロジェクトテスト用ベースクラス
class MultiProjectUITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .multiProject }
}

/// Internal Audit機能テスト用ベースクラス
class InternalAuditUITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .internalAudit }
}
