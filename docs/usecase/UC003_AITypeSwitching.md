# UC003: AIタイプ切り替え

## 概要

異なるAIタイプ（claude, gemini, openai）のエージェントが、それぞれ適切なCLIコマンドで実行されることを検証するシナリオ。

---

## ユースケース目的

### 検証したいこと

1. **ai_type伝播**: エージェントのai_typeがshould_start APIで正しく返される
2. **kickCommand優先**: kickCommandが設定されている場合、ai_typeより優先される
3. **CLI選択**: Coordinatorがai_typeに基づいて適切なCLIを選択する（将来）

### ビジネス価値

- 複数のAIプロバイダーを同一システムで統合管理
- プロジェクトやタスクの特性に応じたAI選択
- カスタムCLIコマンドによる柔軟な拡張

---

## 前提条件

### アプリ側の実装状況

| 機能 | 状態 | 説明 |
|------|------|------|
| Agent.aiType | 実装済み | claude, gemini, openai, other |
| Agent.kickCommand | 実装済み | カスタムCLIコマンド |
| should_start API | 実装済み | ai_typeを返す |

### MCP API

| API | 状態 | 説明 |
|-----|------|------|
| `should_start(agent_id)` | 実装済み | ai_typeを含むレスポンス |

---

## シナリオ

### シナリオ構成

```
エージェント:
  - agt_claude: Claudeエージェント（aiType: claude）
  - agt_custom: カスタムコマンドエージェント（aiType: claude, kickCommand: "echo"）

プロジェクト:
  - prj_uc003: UC003テストプロジェクト（working_dir: /tmp/uc003）

タスク:
  - tsk_claude: Claudeタスク（agt_claude）
  - tsk_custom: カスタムタスク（agt_custom）
```

### 期待される動作

```
1. should_start("agt_claude") → { should_start: true, ai_type: "claude" }
   → Runnerは "claude" コマンドを使用

2. should_start("agt_custom") → { should_start: true, ai_type: "claude", kick_command: "echo" }
   → Runnerは "echo" コマンドを使用（kickCommand優先）
```

### 成功条件

```
1. agt_claudeのshould_start APIが ai_type: "claude" を返す
2. agt_customのshould_start APIが kick_command: "echo" を返す
3. 各Runnerが適切なCLIコマンドで実行される
```

---

## テスト設計

### UIテスト（XCUITest）

UIテストではAPIレスポンスの検証が主な目的：

```swift
// シードデータ
Agent(id: "agt_uc003_claude", name: "UC003 Claude", aiType: .claude, kickCommand: nil)
Agent(id: "agt_uc003_custom", name: "UC003 Custom", aiType: .claude, kickCommand: "echo")

Task(id: "tsk_uc003_claude", projectId: "prj_uc003", assigneeId: "agt_uc003_claude")
Task(id: "tsk_uc003_custom", projectId: "prj_uc003", assigneeId: "agt_uc003_custom")
```

### 検証項目

| # | 検証内容 | 期待結果 |
|---|----------|----------|
| 1 | should_start(agt_claude)のai_type | "claude" |
| 2 | should_start(agt_custom)のkick_command | "echo" |
| 3 | エージェント詳細画面でai_typeが表示される | "Claude" |
| 4 | エージェント詳細画面でkickCommandが表示される | "echo" |

---

## 実装フェーズ

### Phase 1: UIテスト（本テスト）

- XCUITestでシードデータ投入
- エージェント詳細画面でai_type/kickCommandの表示確認
- MCP APIレスポンスの検証（統合テストスクリプト）

### Phase 2: 統合テスト（将来）

- 実際のRunner起動
- echoコマンドでの実行検証
- 出力ファイルの内容確認

---

## 依存関係

### 関連ユースケース

| UC | 関係 |
|----|------|
| UC001 | 単一エージェント実行（基本形） |
| UC002 | system_prompt差異による出力差 |
| **UC003** | **ai_type/kickCommandによるCLI切り替え（本UC）** |
| UC004 | 複数プロジェクト×同一エージェント |

---

## 技術メモ

### AIType enum

```swift
public enum AIType: String, Codable, Sendable, CaseIterable {
    case claude = "claude"
    case gemini = "gemini"
    case openai = "openai"
    case other = "other"
}
```

### should_start APIレスポンス

```json
{
  "should_start": true,
  "ai_type": "claude",
  "kick_command": "echo"  // kickCommandが設定されている場合のみ
}
```

### Runner CLI選択ロジック（将来実装）

```python
# coordinator.py（概念）
def select_cli_command(agent_info):
    if agent_info.get("kick_command"):
        return agent_info["kick_command"]

    ai_type = agent_info.get("ai_type", "claude")
    return {
        "claude": "claude",
        "gemini": "gemini",
        "openai": "openai-cli",
        "other": "claude"  # fallback
    }.get(ai_type, "claude")
```

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-07 | 初版作成 |
