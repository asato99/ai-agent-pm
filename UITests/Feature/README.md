# Feature UIテスト一覧

UC001（エージェントによるタスク実行）を完全にパスさせるために必要なフィーチャーテスト。

---

## UC001 フロー と 必要なフィーチャー

```
[ユーザー操作]
1. タスク作成 ─────────────────── ✅ 実装済み
2. エージェント割り当て ─────────── ✅ 実装済み
3. ステータス → in_progress ────── ✅ UI実装済み
                 │
                 ↓ トリガー
[システム/エージェント]
4. エージェントキック ─────────── ❌ Feature01
5. エージェント認証 ───────────── ❌ Feature02
6. 子タスク作成 ───────────────── ❌ Feature03
7. タスク実行・完了 ───────────── ❌ Feature04
8. 完了通知 ───────────────────── ❌ Feature05
```

---

## Feature01: エージェントキック設定

### 概要
エージェント管理画面でキック方法（起動コマンド/スクリプト）を設定できる。

### テストケース

| ID | テスト名 | 期待結果 |
|----|----------|----------|
| F01-01 | testKickSettingsSectionExists | エージェントフォームに「実行設定」セクションが存在 |
| F01-02 | testKickMethodPicker | 起動方式（CLI/Script/API/Notification）を選択可能 |
| F01-03 | testKickCommandField | 起動コマンド入力フィールドが存在 |
| F01-04 | testKickSettingsSaved | 設定が保存され、再表示時に反映されている |

### 関連UI変更
- `AgentFormView`: 実行設定セクション追加
- `Agent`エンティティ: `kickMethod`, `kickCommand` 属性追加

---

## Feature02: エージェント認証

### 概要
エージェントにパスキーを設定し、MCP接続時の認証に使用する。

### テストケース

| ID | テスト名 | 期待結果 |
|----|----------|----------|
| F02-01 | testAuthSectionExists | エージェントフォームに「認証設定」セクションが存在 |
| F02-02 | testPasskeyField | パスキー入力フィールドが存在（SecureField） |
| F02-03 | testPasskeyMasked | 入力されたパスキーがマスク表示される |
| F02-04 | testAuthLevelPicker | 認証レベル（0/1/2）を選択可能 |
| F02-05 | testPasskeySaved | パスキーが保存される（表示はマスク） |

### 関連UI変更
- `AgentFormView`: 認証設定セクション追加
- `Agent`エンティティ: `passkey`, `authLevel` 属性追加

---

## Feature03: キックトリガー

### 概要
タスクステータスがin_progressに変更されたとき、キックが実行される。

### テストケース

| ID | テスト名 | 期待結果 |
|----|----------|----------|
| F03-01 | testKickTriggeredOnStatusChange | in_progress変更時にキック処理が呼ばれる |
| F03-02 | testKickStatusDisplayed | キック状態（成功/失敗）がUI上に表示される |
| F03-03 | testKickLogVisible | キックのログ/履歴が確認可能 |

### 関連UI変更
- `TaskDetailView`: キック状態表示
- `UpdateTaskStatusUseCase`: キック処理呼び出し追加

---

## Feature04: ~~子タスク管理~~ → 削除

### 概要
~~親タスクの下に子タスクを作成・管理できる。~~

**削除理由**: 要件変更により、サブタスク（`parentTaskId`）は不要となりました。
タスク間の関係は `dependencies`（依存関係）で表現します。
参照: `docs/requirements/TASKS.md`, `docs/usecase/UC001_TaskExecutionByAgent.md`

### テストケース
（すべて削除 - 実装対象外）

### 関連変更
- `parentTaskId` を Task エンティティから削除
- 依存関係（`dependencies`）で作業タスク間の関係を表現

---

## Feature05: 完了通知

### 概要
タスク完了時に親（上位エージェント/ユーザー）に通知される。

### テストケース

| ID | テスト名 | 期待結果 |
|----|----------|----------|
| F05-01 | testCompletionCreatesHandoff | タスク完了時にHandoffが自動作成される |
| F05-02 | testHandoffVisibleInTaskDetail | 作成されたHandoffがタスク詳細に表示される |
| F05-03 | testNotificationToParent | 親エージェント/ユーザーに通知が送られる |
| F05-04 | testAllDependencyTasksDoneEnablesComplete | 全依存タスク完了時にタスクを完了可能 |

### 関連UI変更
- `TaskDetailView`: 完了通知セクション
- `UpdateTaskStatusUseCase`: Handoff自動作成ロジック

---

## Feature06: プロジェクト作業ディレクトリ

### 概要
プロジェクトにworkingDirectory（作業ディレクトリ）を設定し、Claude Codeエージェントがファイルを作成する場所を指定。

### テストケース

| ID | テスト名 | 期待結果 |
|----|----------|----------|
| F06-01 | testWorkingDirectoryFieldExists | プロジェクトフォームに作業ディレクトリ入力フィールドが存在 |
| F06-02 | testWorkingDirectorySaved | 設定した作業ディレクトリが保存される |
| F06-03 | testWorkingDirectoryDisplayed | プロジェクト詳細に作業ディレクトリが表示される |

### 関連UI変更
- `ProjectFormView`: 作業ディレクトリ入力フィールド追加
- `Project`エンティティ: `workingDirectory` 属性追加

---

## Feature07: タスク出力情報 → 削除

### 概要
~~タスクに出力ファイル名と説明を設定。~~

**削除理由**: 要件変更により、ファイル名や内容はタスクの`description`（指示内容）で与えるべき。
成果物管理はエージェントの責務であり、PMアプリの責務ではない。
参照: `docs/usecase/UC001_TaskExecutionByAgent.md`

### テストケース
（すべて削除 - 実装対象外）

---

## Feature08: エージェントキック実行

### 概要
タスクステータスがin_progressに変更されたとき、アサイン先エージェントをキック（Claude Code CLI起動）する。

### テストケース

| ID | テスト名 | 期待結果 |
|----|----------|----------|
| F08-01 | testKickSuccessRecordedInHistory | in_progress変更後、Historyにキック記録が表示される |
| F08-02 | testKickFailureShowsErrorForMissingWorkingDirectory | 作業ディレクトリ未設定時にエラーダイアログが表示される |
| F08-03 | testKickSkippedForAgentWithoutKickMethod | kickMethod未設定エージェントでキックがスキップされる |

### 関連UI変更
- `ClaudeCodeKickService`: Claude Code CLI起動処理
- `TaskDetailView`: 履歴表示
- `UpdateTaskStatusUseCase`: キック処理呼び出し

### 統合テスト

実際のClaude CLI起動とファイル作成を確認するスクリプト:

```bash
# UITest経由の統合テスト（ファイル作成と内容を検証）
./scripts/tests/test_uc001_integration.sh

# スタンドアロンCLIテスト
./scripts/tests/test_uc001_e2e.sh
```

検証項目:
- ファイルが指定ディレクトリに作成されること
- ファイル内容に期待するテキストが含まれること

---

## 実装順序（TDD）

```
Phase 1: エージェント設定の拡張
├── Feature01: キック設定 ✅
└── Feature02: 認証設定 ✅

Phase 2: キック機構
├── Feature03: キックトリガー ✅
└── Feature08: キック実行 ✅

Phase 3: プロジェクト設定
└── Feature06: 作業ディレクトリ ✅

Phase 4: 完了フロー
└── Feature05: 完了通知 ✅

削除:
├── Feature04: 子タスク管理（dependenciesで代替）
└── Feature07: タスク出力情報（descriptionで代替）
```

---

## テスト実行コマンド

```bash
# 全Featureテスト
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/Feature01_AgentKickSettingsTests \
  -only-testing:AIAgentPMUITests/Feature02_AgentAuthTests \
  -only-testing:AIAgentPMUITests/Feature03_KickTriggerTests \
  -only-testing:AIAgentPMUITests/Feature05_CompletionTests \
  -only-testing:AIAgentPMUITests/Feature06_ProjectWorkingDirectoryTests \
  -only-testing:AIAgentPMUITests/Feature08_AgentKickExecutionTests

# 個別Feature
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/Feature08_AgentKickExecutionTests

# 統合テスト（実際のClaude CLI起動）
./scripts/tests/test_uc001_integration.sh
```
