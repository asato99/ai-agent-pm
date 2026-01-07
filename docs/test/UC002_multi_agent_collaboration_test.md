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
| `scripts/tests/test_uc002_multi_agent.sh` | マルチエージェント統合テスト | system_promptの振る舞い検証 |

### 実行コマンド

```bash
# UC002統合テストを実行
./scripts/tests/test_uc002_multi_agent.sh

# テストディレクトリを保持する場合
./scripts/tests/test_uc002_multi_agent.sh --keep
```

### 統合テストの流れ

```
1. テスト環境準備
2. MCPデーモン起動
3. テストデータ投入（詳細ライター/簡潔ライターエージェント）
4. 両Runner起動（両方claude CLI）
5. タスク実行待機
6. 出力ファイル検証（文字数比較）
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
| テスト種別 | E2E UIテスト | ユースケース統合テスト |
| 実行方法 | xcodebuild (アプリ起動) | swift test (スクリプト) |
| テストファイル | `UITests/USECASE/` | `Tests/UseCaseTests/` |
| 依存 | シードデータ、UI要素 | モックリポジトリ |

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

```
test_uc002_multi_agent.sh
├── Step 1: テスト環境準備
├── Step 2: MCPサーバービルド
├── Step 3: Runnerセットアップ確認
├── Step 4: MCPデーモン起動
├── Step 5: テストデータ投入
│   ├── 詳細ライター（system_prompt=詳細版）
│   └── 簡潔ライター（system_prompt=簡潔版）
├── Step 6: Runner起動（詳細ライター）
├── Step 7: Runner起動（簡潔ライター）
├── Step 8: タスク実行待機（max 180s）
└── Step 9: 出力検証
    ├── 詳細版: > 300文字 または「背景」を含む
    └── 簡潔版: 詳細版より短い
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
| 2026-01-07 | UC001アプリ統合テスト完成: `test_uc001_app_integration.sh`がリファレンス実装として利用可能 |

---

## 技術メモ

### UC001との差異

UC001では `test_uc001_app_integration.sh` でアプリ統合テストを実現：
- XCUITest → アプリ起動 + シードデータ + UI操作でステータス変更
- MCPデーモン → 同一DB使用
- Runner → タスク検出 + CLI実行

UC002をアプリ統合にする場合の考慮点：
- **2つのエージェント**が必要（詳細ライター、簡潔ライター）
- **2つのRunner**が必要（各エージェント用）
- **2つのタスク**のステータス変更が必要
- XCUITestで2つのタスクを順次in_progressに変更する必要あり

現状の `test_uc002_multi_agent.sh` はDB直接投入方式で動作確認済み。
アプリ統合版は将来の拡張として検討可能。
