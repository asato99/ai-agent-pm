# UC003: AIモデル切り替え

## 概要

異なるAIモデル（Claude Sonnet 4.5, Claude Opus 4, Gemini 2.0 Flash等）のエージェントが、それぞれ適切なCLIコマンドとモデル指定で実行されることを検証するシナリオ。

---

## ユースケース目的

### 検証したいこと

1. **モデル情報伝播**: エージェントのaiType（モデル指定）がshould_start APIで正しく返される
2. **CLI選択**: Coordinatorがモデル情報に基づいて適切なCLIとモデル引数を選択する

### ビジネス価値

- 複数のAIモデルを同一システムで統合管理
- タスクの複雑さに応じたモデル選択（簡単なタスクはSonnet、複雑なタスクはOpus）

---

## 前提条件

### アプリ側の実装状況

| 機能 | 状態 | 説明 |
|------|------|------|
| Agent.aiType | 実装済み | モデル指定（claudeSonnet4_5, claudeOpus4, gemini2Flash等） |
| should_start API | 実装済み | ai_type（モデル情報）を返す |

### MCP API

| API | 状態 | 説明 |
|-----|------|------|
| `should_start(agent_id)` | 実装済み | ai_typeを含むレスポンス |

---

## シナリオ

### シナリオ構成

```
エージェント:
  - agt_uc003_sonnet: Sonnetエージェント（aiType: claudeSonnet4_5）
  - agt_uc003_opus: Opusエージェント（aiType: claudeOpus4）

プロジェクト:
  - prj_uc003: UC003テストプロジェクト（working_dir: /tmp/uc003）

タスク:
  - tsk_uc003_sonnet: Sonnetタスク（agt_uc003_sonnet）
  - tsk_uc003_opus: Opusタスク（agt_uc003_opus）
```

### 期待される動作

```
1. should_start("agt_uc003_sonnet") → { should_start: true, ai_type: "claude-sonnet-4-5" }
   → Runnerは "claude" コマンド + Sonnet 4.5モデルを使用

2. should_start("agt_uc003_opus") → { should_start: true, ai_type: "claude-opus-4" }
   → Runnerは "claude" コマンド + Opus 4モデルを使用
```

### 成功条件

```
1. agt_uc003_sonnetのshould_start APIが ai_type: "claude-sonnet-4-5" を返す
2. agt_uc003_opusのshould_start APIが ai_type: "claude-opus-4" を返す
3. 各Runnerが適切なCLIコマンド/モデルで実行される
```

---

## テスト設計

### UIテスト（XCUITest）

UIテストではモデル設定とステータス変更の検証が主な目的：

```swift
// シードデータ
Agent(id: "agt_uc003_sonnet", name: "UC003 Sonnet Agent", aiType: .claudeSonnet4_5)
Agent(id: "agt_uc003_opus", name: "UC003 Opus Agent", aiType: .claudeOpus4)

Task(id: "tsk_uc003_sonnet", projectId: "prj_uc003", assigneeId: "agt_uc003_sonnet")
Task(id: "tsk_uc003_opus", projectId: "prj_uc003", assigneeId: "agt_uc003_opus")
```

### 検証項目

| # | 検証内容 | 期待結果 |
|---|----------|----------|
| 1 | should_start(agt_uc003_sonnet)のai_type | "claude-sonnet-4-5" |
| 2 | should_start(agt_uc003_opus)のai_type | "claude-opus-4" |
| 3 | エージェント詳細画面でモデルが表示される | "Claude Sonnet 4.5" / "Claude Opus 4" |

---

## 実装フェーズ

### Phase 1: UIテスト

- XCUITestでシードデータ投入
- エージェント詳細画面でai_typeの表示確認
- タスクのステータス変更確認

### Phase 2: 統合テスト（実装済み）

- **テストスクリプト**: `scripts/tests/test_uc003_app_integration.sh`
- **XCUITest**: `testE2E_UC003_AITypeSwitching_Integration`
- 実際のCoordinator/Runner起動
- Coordinatorがai_typeに基づいてCLI選択
- 出力ファイルの内容確認

#### 統合テストアーキテクチャ（Phase 4 Coordinator）

```
1. Coordinator起動（MCPソケット待機）
2. アプリ起動（MCP Daemon自動起動）
3. XCUITestでシードデータ投入 + ステータス変更
4. Coordinatorがshould_start()でタスク検出
5. エージェントごとにCLIコマンド選択:
   - agt_uc003_sonnet: ai_type=claude-sonnet-4-5 → "claude" コマンド + Sonnetモデル
   - agt_uc003_opus: ai_type=claude-opus-4 → "claude" コマンド + Opusモデル
6. Agent Instanceがタスク完了 → Done状態に
```

---

## 依存関係

### 関連ユースケース

| UC | 関係 |
|----|------|
| UC001 | 単一エージェント実行（基本形） |
| UC002 | system_prompt差異による出力差 |
| **UC003** | **ai_typeによるモデル切り替え（本UC）** |
| UC004 | 複数プロジェクト×同一エージェント |

---

## 技術メモ

### AIType enum

```swift
public enum AIType: String, Codable, Sendable, CaseIterable {
    // Claude models
    case claudeOpus4 = "claude-opus-4"
    case claudeSonnet4_5 = "claude-sonnet-4-5"
    case claudeSonnet4 = "claude-sonnet-4"

    // Gemini models
    case gemini2Flash = "gemini-2.0-flash"
    case gemini2Pro = "gemini-2.0-pro"

    // OpenAI models
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"

    // Other/Custom
    case other = "other"

    // プロバイダー名（Coordinator設定用）
    var provider: String { /* claude, gemini, openai, other */ }
    // CLIコマンド名（Runner用）
    var cliCommand: String { /* claude, gemini, openai */ }
    // モデルID（API呼び出し用）
    var modelId: String { /* claude-opus-4-20250514 等 */ }
}
```

### should_start APIレスポンス

```json
{
  "should_start": true,
  "provider": "claude",                    // プロバイダー（claude, gemini, openai, other）
  "model": "claude-sonnet-4-5",            // 具体的なモデル
  "ai_type": "claude-sonnet-4-5"           // 後方互換性のため維持（非推奨）
}
```

### Runner CLI選択ロジック

```python
# coordinator.py - _spawn_instance()
def spawn_instance(provider, model, ...):
    # providerベースでCLI選択
    provider_config = config.get_provider(provider)
    cli_command = provider_config.cli_command
    cli_args = provider_config.cli_args
```

### データ構造

```
App (Agent.aiType)
    ↓
    AIType enum:
    - rawValue: "claude-sonnet-4-5" (model)
    - provider: "claude"
    ↓
MCP API (should_start response)
    ↓
    {
      "provider": "claude",
      "model": "claude-sonnet-4-5"
    }
    ↓
Coordinator
    ↓
    provider → CLI command
    model → ログ/環境変数に使用
```

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-07 | 初版作成 |
| 2026-01-08 | Phase 2統合テスト実装（Coordinator連携） |
| 2026-01-08 | provider/model構造に変更（ai_typeを分離） |
| 2026-01-12 | kickCommand削除（非推奨機能の完全削除） |
