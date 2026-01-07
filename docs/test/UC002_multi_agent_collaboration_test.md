# UC002: マルチエージェント協調作業 テストシナリオ

**対応ユースケース**: `docs/usecase/UC002_MultiAgentCollaboration.md`
**テストクラス**: `UC002_MultiAgentCollaborationTests`
**最終更新**: 2026-01-07

---

## テスト実行方法

**bashスクリプトから実行される統合テスト**

### 利用可能なスクリプト

| スクリプト | 説明 | 用途 |
|-----------|------|------|
| `scripts/tests/test_uc002_app_integration.sh` | **真の統合テスト（推奨）** | アプリ+MCP+Runner E2E |
| `scripts/tests/test_uc002_multi_agent.sh` | DB直接投入版 | 簡易検証用 |

### 実行コマンド

```bash
# UC002アプリ統合テストを実行（推奨）
./scripts/tests/test_uc002_app_integration.sh

# テストディレクトリを保持する場合
./scripts/tests/test_uc002_app_integration.sh --keep

# DB直接投入版（簡易検証）
./scripts/tests/test_uc002_multi_agent.sh
```

### アプリ統合テストの流れ（推奨）

```
test_uc002_app_integration.sh
1. テスト環境準備（2つの作業ディレクトリ）
2. MCPサーバービルド + アプリビルド
3. XCUITest実行（アプリ起動→シードデータ投入→UI操作でステータス変更）
4. MCPデーモン起動（XCUITestが作成した共有DBを使用）
5. 両Runner起動（詳細ライター用、簡潔ライター用）
6. タスク実行待機
7. 出力ファイル検証（文字数比較）
```

### DB直接投入版の流れ（簡易検証）

```
test_uc002_multi_agent.sh
1. テスト環境準備
2. MCPデーモン起動
3. テストデータ投入（DB直接書き込み）
4. 両Runner起動
5. タスク実行待機
6. 出力ファイル検証
```

**注**: ai_typeの切り替え検証はUC003で実施

### 前提条件

- mcp-server-pm ビルド済み
- Xcodeビルド環境

---

## 設計原則

### テストの目的

「異なるsystem_prompt = 異なる専門家」というコンセプトの実証：
- 同じタスク指示でも、system_promptによって成果物が異なる

### テスト種別

**UC002はユースケース層の統合テストであり、UIテストではない。**

検証内容:
- **出力の差異**: 異なるsystem_promptで異なる出力が生成される
- **文字数比較**: 詳細版 > 簡潔版

**注**: ai_typeの切り替え検証はUC003で実施

### UC001との違い

| 項目 | UC001 | UC002 |
|------|-------|-------|
| テスト種別 | E2E UIテスト | E2E UIテスト |
| 実行方法 | xcodebuild (アプリ起動) | xcodebuild (アプリ起動) |
| テストファイル | `UITests/USECASE/UC001_*.swift` | `UITests/USECASE/UC002_*.swift` |
| エージェント数 | 1 | 2（詳細/簡潔ライター） |
| Runner数 | 1 | 2（各エージェント用） |
| 検証対象 | ファイル作成の成功 | ファイル内容の差異（文字数比較） |

---

## 必須シードデータ

| ID | 種別 | 条件 | 用途 |
|----|------|------|------|
| agt_detailed_writer | Agent | aiType=claude, systemPrompt=「詳細で包括的に...」 | 詳細ライター |
| agt_concise_writer | Agent | aiType=claude, systemPrompt=「簡潔に要点のみ...」 | 簡潔ライター |
| prj_uc002_test | Project | テスト用 | テスト用プロジェクト |

### エージェント設定詳細

```swift
// 詳細ライター（Claude / 詳細system_prompt）
Agent(
    id: "agt_detailed_writer",
    name: "詳細ライター",
    type: .ai,
    aiType: .claude,
    systemPrompt: "詳細で包括的なドキュメントを作成してください。背景、目的、使用例を必ず含めてください。"
)

// 簡潔ライター（Claude / 簡潔system_prompt）
Agent(
    id: "agt_concise_writer",
    name: "簡潔ライター",
    type: .ai,
    aiType: .claude,
    systemPrompt: "簡潔に要点のみ記載してください。箇条書きで3項目以内にまとめてください。"
)
```

**注**: 両エージェントともclaude。system_promptの差異による出力の違いを検証。

---

## テストフロー

### アプリ統合テスト（推奨）

```
test_uc002_app_integration.sh
├── Step 1: テスト環境準備（2ディレクトリ作成）
├── Step 2: MCPサーバービルド
├── Step 3: アプリビルド
├── Step 4: Runnerセットアップ確認
├── Step 5: XCUITest実行
│   ├── アプリ起動（-UITesting -UITestScenario:UC002）
│   ├── シードデータ投入（seedUC002Data()）
│   └── UI操作でステータス変更（両タスク → in_progress）
├── Step 6: DB状態確認（動的パス検出）
├── Step 7: MCPデーモン起動（共有DB使用）
├── Step 8: Runner起動（詳細+簡潔の2つ）
├── Step 9: タスク実行待機（max 180s）
└── Step 10: 出力検証
    ├── 詳細版: > 300文字 または「背景」を含む
    └── 簡潔版: 詳細版より短い
```

### DB直接投入版

```
test_uc002_multi_agent.sh
├── Step 1: テスト環境準備
├── Step 2: MCPサーバービルド
├── Step 3: Runnerセットアップ確認
├── Step 4: MCPデーモン起動
├── Step 5: テストデータ投入（DB直接）
├── Step 6-7: Runner起動（詳細+簡潔）
├── Step 8: タスク実行待機
└── Step 9: 出力検証
```

---

## 検証基準

### 出力検証

| 検証項目 | 詳細ライター | 簡潔ライター |
|----------|--------------|--------------|
| ファイル作成 | PROJECT_SUMMARY.md | PROJECT_SUMMARY.md |
| 文字数基準 | > 300文字 または「背景」含む | 詳細版より短い |
| system_prompt | 「詳細で包括的に...」 | 「簡潔に要点のみ...」 |

### 成功条件

```bash
# 両方のファイルが作成される
[ -f "$TEST_DIR/detailed/PROJECT_SUMMARY.md" ]
[ -f "$TEST_DIR/concise/PROJECT_SUMMARY.md" ]

# 詳細版は長い、または「背景」を含む
DETAILED_CHARS > 300 || grep -q "背景" detailed/PROJECT_SUMMARY.md

# 簡潔版は詳細版より短い
CONCISE_CHARS < DETAILED_CHARS
```

---

## 実行例

```
==========================================
UC002 Multi-Agent Integration Test
(system_prompt差異による出力検証)
==========================================

Step 5: Seeding test data
  Detailed Writer: agt_detailed_writer (system_prompt=詳細版)
  Concise Writer: agt_concise_writer (system_prompt=簡潔版)

Step 8: Waiting for task execution (max 180s)
✓ Concise writer created PROJECT_SUMMARY.md
✓ Detailed writer created PROJECT_SUMMARY.md

Step 9: Verifying outputs
Detailed output: 2017 characters
✓ Detailed output meets criteria
Concise output: 637 characters
  Ratio (detailed/concise): 3x
✓ Concise output is shorter than detailed

==========================================
UC002 Integration Test: PASSED

Verified:
  - Detailed writer created comprehensive output
  - Concise writer created brief output
  - Different system_prompts produced different outputs
```

---

## 関連ユースケース

| UC | 検証内容 |
|----|----------|
| UC001 | 単一エージェントによるタスク実行 |
| UC002 | system_promptによる出力差異（本テスト） |
| UC003 | ai_typeによるCLI切り替え（将来実装） |

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-07 | 初版作成: UC002テストシナリオ設計 |
| 2026-01-07 | 統合テスト実装: 両エージェントclaudeに変更、ai_type検証はUC003へ分離 |
| 2026-01-07 | UC001アプリ統合テスト完成: `test_uc001_app_integration.sh`がリファレンス実装 |
| 2026-01-07 | **UC002アプリ統合テスト実装**: `test_uc002_app_integration.sh`完成 |

---

## 技術メモ

### 実装ファイル

| ファイル | 役割 |
|----------|------|
| `Sources/App/AIAgentPMApp.swift` | TestScenario.uc002、seedUC002Data() |
| `UITests/Base/UITestBase.swift` | UC002UITestCase基底クラス |
| `UITests/USECASE/UC002_MultiAgentCollaborationTests.swift` | UC002 UITest |
| `scripts/tests/test_uc002_app_integration.sh` | アプリ統合テストスクリプト |

### シードデータ詳細

```swift
// seedUC002Data()で作成されるデータ

// プロジェクト（2つ - 各ライターに対応）
Project(id: "prj_uc002_detailed", workingDirectory: "/tmp/uc002_detailed")
Project(id: "prj_uc002_concise", workingDirectory: "/tmp/uc002_concise")

// エージェント（2つ - 異なるsystem_prompt）
Agent(id: "agt_detailed_writer", systemPrompt: "詳細で包括的に...")
Agent(id: "agt_concise_writer", systemPrompt: "簡潔に要点のみ...")

// タスク（2つ - backlog → UIテストでin_progressに）
Task(id: "tsk_uc002_detailed", assigneeId: "agt_detailed_writer")
Task(id: "tsk_uc002_concise", assigneeId: "agt_concise_writer")

// 認証情報
AgentCredential(agentId: "agt_detailed_writer", passkey: "test_passkey_detailed")
AgentCredential(agentId: "agt_concise_writer", passkey: "test_passkey_concise")
```

### DB共有の仕組み

UC001と同じアーキテクチャ:
1. XCUITestアプリが `NSTemporaryDirectory()` にDBを作成
2. 実際のパスは `/private/var/folders/.../T/AIAgentPM_UITest.db`
3. 統合テストスクリプトが `find` コマンドでパスを動的検出
4. MCPデーモンは `AIAGENTPM_DB_PATH` 環境変数でDBパスを指定
