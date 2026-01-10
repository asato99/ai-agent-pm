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
    case uc001 = "UC001"           // UC001: エージェントによるタスク実行（Runner統合テスト用）
    case uc002 = "UC002"           // UC002: マルチエージェント協調（system_prompt差異検証）
    case uc003 = "UC003"           // UC003: AIタイプ切り替え（kickCommand検証）
    case uc004 = "UC004"           // UC004: 複数プロジェクト×同一エージェント
    case uc005 = "UC005"           // UC005: マネージャー→ワーカー委任
    case uc006 = "UC006"           // UC006: 複数ワーカーへのタスク割り当て
    case uc007 = "UC007"           // UC007: 依存関係のあるタスク実行（実装→テスト）
    case uc008 = "UC008"           // UC008: タスクブロックによる作業中断
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
        // Phase 5: MCP_COORDINATOR_TOKEN を渡してCoordinator APIを認可
        // UIテスト用の固定トークンを使用（テストスクリプトと同じ値）
        var launchEnv: [String: String] = [
            "XCUI_ENABLE_ACCESSIBILITY": "1",
            // Phase 5: Integration test coordinator token
            // This must match the token used in test_uc00X_app_integration.sh scripts
            "MCP_COORDINATOR_TOKEN": "test_coordinator_token_uc001"
        ]
        app.launchEnvironment = launchEnv

        // システムダイアログの自動ハンドリングを設定
        // macOSの通知許可ダイアログ等がXCUITestを阻害する問題を回避
        addUIInterruptionMonitor(withDescription: "System Dialog") { alert -> Bool in
            print("⚠️ System dialog detected, attempting to dismiss...")
            // "許可しない" や "Don't Allow" などのボタンを探して押す
            for buttonLabel in ["許可しない", "Don't Allow", "OK", "閉じる", "Close", "Cancel", "キャンセル"] {
                let button = alert.buttons[buttonLabel]
                if button.exists {
                    print("  Clicking '\(buttonLabel)' button")
                    button.click()
                    return true
                }
            }
            // ボタンが見つからない場合、最初のボタンを押す
            if alert.buttons.count > 0 {
                print("  Clicking first button")
                alert.buttons.firstMatch.click()
                return true
            }
            return false
        }

        // アプリを起動
        print("🚀 Launching app...")
        app.launch()
        print("✅ App launched, state: \(app.state.rawValue)")

        // アプリの起動完了を待つ
        print("⏳ Waiting for window...")
        let window = app.windows.firstMatch
        if window.waitForExistence(timeout: 15) {
            print("✅ Window found, waiting for UI to stabilize...")
            // ウィンドウが見つかった場合、データシードの完了を待つ
            Thread.sleep(forTimeInterval: 3.0)
            // ウィンドウを最前面に
            app.activate()
            Thread.sleep(forTimeInterval: 0.5)

            // カラム幅を220pxに設定したため、5カラム（1100px）がデフォルトウィンドウに収まる
            Thread.sleep(forTimeInterval: 0.5)
        } else {
            // ウィンドウが見つからない場合
            print("⚠️ Window not found after 15 seconds")
            print("App state: \(app.state.rawValue)")
            print("Windows count: \(app.windows.count)")
            Thread.sleep(forTimeInterval: 3.0)
            app.activate()
            Thread.sleep(forTimeInterval: 2.0)
        }
        print("🏁 Setup complete")
    }

    override func tearDownWithError() throws {
        // MCPデーモンがバックグラウンドで動作しているため、
        // 明示的にアプリを終了させてデーモン停止を待つ
        if app != nil {
            app.terminate()
            // デーモン停止のための猶予時間
            Thread.sleep(forTimeInterval: 2.0)
        }
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

/// UC001テスト用ベースクラス（Runner統合テスト用）
class UC001UITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .uc001 }
}

/// UC002テスト用ベースクラス（マルチエージェント協調テスト用）
class UC002UITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .uc002 }
}

/// UC003テスト用ベースクラス（AIタイプ切り替えテスト用）
class UC003UITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .uc003 }
}

/// UC004テスト用ベースクラス（複数プロジェクト×同一エージェントテスト用）
class UC004UITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .uc004 }
}

/// UC005テスト用ベースクラス（マネージャー→ワーカー委任テスト用）
class UC005UITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .uc005 }
}

/// UC006テスト用ベースクラス（複数ワーカーへのタスク割り当てテスト用）
class UC006UITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .uc006 }
}

/// UC007テスト用ベースクラス（依存関係のあるタスク実行テスト用）
class UC007UITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .uc007 }
}

/// UC008テスト用ベースクラス（タスクブロックによる作業中断テスト用）
class UC008UITestCase: AIAgentPMUITestCase {
    override var testScenario: UITestScenario { .uc008 }
}
