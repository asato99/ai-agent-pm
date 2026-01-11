# UC009: エージェントとのチャット通信 テストシナリオ

**対応ユースケース**: `docs/usecase/UC009_ChatCommunication.md`
**テストクラス**: `UC009_ChatCommunicationTests`
**最終更新**: 2026-01-11

---

## テスト実行方法

**bashスクリプトから実行される統合テスト**

### 利用可能なスクリプト

| スクリプト | 説明 | 用途 |
|-----------|------|------|
| `scripts/tests/test_uc009_app_integration.sh` | **アプリ統合テスト** | App→XCUITest→MCP→Runner→CLI のE2E |

### 実行コマンド

```bash
# アプリ統合テスト
./scripts/tests/test_uc009_app_integration.sh

# テストディレクトリを保持する場合
./scripts/tests/test_uc009_app_integration.sh --keep
```

### アプリ統合テストの流れ

```
1. テスト環境準備（/tmp/uc009）
2. ビルド（MCP Server + App）
3. Runner準備確認
4. Coordinator起動（MCPソケット待機）
5. XCUITest実行
   ├── アプリ起動（-UITesting -UITestScenario:UC009）
   ├── TestDataSeederによるシードデータ投入
   ├── エージェントアバターをクリック → チャット画面表示
   └── メッセージ送信「あなたの名前を教えてください」
6. エージェント起動待機
7. 応答待機（最大60秒）
8. 応答検証（エージェント名が含まれるか）
9. ファイル検証（chat.jsonlの内容）
```

### 前提条件

- Claude CLI インストール済み
- Python仮想環境または`aiagent_runner`インストール済み
- Xcodeビルド環境

---

## テストデータ（シードデータ）

### プロジェクト

| フィールド | 値 |
|-----------|-----|
| ID | `prj_uc009` |
| 名前 | UC009 Chat Test |
| workingDirectory | `/tmp/uc009` |
| status | active |

### エージェント

| フィールド | 値 |
|-----------|-----|
| ID | `agt_uc009_chat` |
| 名前 | chat-responder |
| type | worker |
| status | active |
| assignedProjects | [`prj_uc009`] |

---

## テストシナリオ

### シナリオ1: 名前を聞いて応答を受け取る

**目的**: チャット通信の基本フローが正常に動作することを確認

**手順**:

| ステップ | 操作 | 期待結果 |
|---------|------|---------|
| 1 | アプリ起動 | ウィンドウ表示 |
| 2 | プロジェクト「UC009 Chat Test」をクリック | TaskBoardView表示 |
| 3 | ヘッダーのエージェントアバター「chat-responder」をクリック | 第3カラムにAgentChatView表示 |
| 4 | メッセージ入力「あなたの名前を教えてください」 | テキストフィールドに入力される |
| 5 | 送信ボタンをクリック | メッセージがチャット画面に表示される |
| 6 | 応答を待機（最大60秒） | エージェントからの応答が表示される |
| 7 | 応答内容を検証 | 「chat-responder」を含む応答 |

---

## 検証項目（アサーション）

### 必須アサーション

| # | 検証項目 | 検証方法 | 期待値 |
|---|----------|---------|--------|
| 1 | チャット画面表示 | AgentChatViewが第3カラムに表示 | 表示される |
| 2 | メッセージ送信 | 送信ボタンクリック後、メッセージ表示 | ユーザーメッセージが表示 |
| 3 | エージェント応答 | 60秒以内に応答メッセージ表示 | 応答が表示される |
| 4 | 応答内容 | 応答テキストにエージェント名を含む | "chat-responder"を含む |

### ファイル検証

| # | 検証項目 | 検証方法 | 期待値 |
|---|----------|---------|--------|
| 5 | chat.jsonl作成 | ファイル存在確認 | ファイルが存在 |
| 6 | ユーザーメッセージ記録 | sender="user"の行を検索 | 1行以上存在 |
| 7 | エージェント応答記録 | sender="agent"の行を検索 | 1行以上存在 |

---

## ファイル構成

### テスト前

```
/tmp/uc009/
└── (空)
```

### テスト後（期待）

```
/tmp/uc009/
└── .ai-pm/
    └── agents/
        └── agt_uc009_chat/
            └── chat.jsonl
```

### chat.jsonl内容（例）

```jsonl
{"id":"msg_abc123","sender":"user","content":"あなたの名前を教えてください","createdAt":"2026-01-11T10:00:00Z"}
{"id":"msg_def456","sender":"agent","content":"私の名前はchat-responderです。何かお手伝いできることはありますか？","createdAt":"2026-01-11T10:00:05Z"}
```

---

## XCUITestコード概要

```swift
final class UC009_ChatCommunicationTests: XCTestCase {

    func testChatWithAgent_AskName() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-UITestScenario:UC009"]
        app.launch()

        // 1. プロジェクト選択
        let project = app.outlines.buttons["UC009 Chat Test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.click()

        // 2. エージェントアバターをクリック
        let agentAvatar = app.buttons["agent-avatar-agt_uc009_chat"]
        XCTAssertTrue(agentAvatar.waitForExistence(timeout: 5))
        agentAvatar.click()

        // 3. チャット画面表示確認
        let chatView = app.groups["agent-chat-view"]
        XCTAssertTrue(chatView.waitForExistence(timeout: 5))

        // 4. メッセージ入力・送信
        let inputField = app.textFields["chat-input-field"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 5))
        inputField.click()
        inputField.typeText("あなたの名前を教えてください")

        let sendButton = app.buttons["chat-send-button"]
        sendButton.click()

        // 5. 応答待機（最大60秒）
        let agentMessage = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'chat-responder'")
        ).firstMatch
        XCTAssertTrue(agentMessage.waitForExistence(timeout: 60))
    }
}
```

---

## スクリプト実装概要

### test_uc009_app_integration.sh

```bash
#!/bin/bash
set -e

# 1. 環境準備
TEST_DIR="/tmp/uc009"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# 2. ビルド
xcodebuild build -scheme AIAgentPM ...
swift build --product mcp-server-pm ...

# 3. Coordinator起動
python -m aiagent_runner --coordinator ... &

# 4. XCUITest実行
xcodebuild test \
  -scheme AIAgentPM \
  -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/UC009_ChatCommunicationTests

# 5. ファイル検証
CHAT_FILE="$TEST_DIR/.ai-pm/agents/agt_uc009_chat/chat.jsonl"
if [ -f "$CHAT_FILE" ]; then
    echo "✓ chat.jsonl created"
    grep -q '"sender":"agent"' "$CHAT_FILE" && echo "✓ Agent response recorded"
else
    echo "✗ chat.jsonl not found"
    exit 1
fi

echo "UC009 Chat Communication Test: PASSED"
```

---

## 設計原則

### E2Eテストの必須ルール

1. **単一テストメソッド**: 1回のアプリ起動で全フローを検証
2. **リアクティブ検証**: 全ての「操作→UI反映」をアサート
3. **ハードアサーション**: 条件分岐禁止、必ず失敗させる
4. **タイムアウト設定**: 応答待機は最大60秒

### テスト失敗時の原則

- チャット画面が表示されない → **テスト失敗**
- メッセージが送信されない → **テスト失敗**
- 応答が60秒以内に来ない → **テスト失敗**
- 応答にエージェント名が含まれない → **テスト失敗**

---

## 備考

- チャット通信はファイルベース（.ai-pm/agents/{id}/chat.jsonl）
- エージェント起動理由はDBで管理（pending_agent_purposes）
- 参照: docs/design/CHAT_FEATURE.md
- 参照: docs/usecase/UC009_ChatCommunication.md
