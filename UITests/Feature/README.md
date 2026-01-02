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

## Feature04: 子タスク管理

### 概要
親タスクの下に子タスクを作成・管理できる。

### テストケース

| ID | テスト名 | 期待結果 |
|----|----------|----------|
| F04-01 | testCreateSubtaskButton | タスク詳細に「子タスク追加」ボタンが存在 |
| F04-02 | testSubtaskFormOpens | ボタンクリックで子タスク作成フォームが開く |
| F04-03 | testSubtaskDisplayedUnderParent | 作成した子タスクが親タスク詳細に表示される |
| F04-04 | testSubtaskStatusIndependent | 子タスクのステータスを個別に変更可能 |
| F04-05 | testSubtaskCountBadge | 親タスクに子タスク数バッジが表示される |

### 関連UI変更
- `TaskDetailView`: 子タスクセクション追加
- `TaskFormView`: 親タスクID指定モード追加
- `Task`エンティティ: `parentTaskId`（既存）を活用

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
| F05-04 | testAllSubtasksDoneEnablesParentComplete | 全子タスク完了時に親タスクを完了可能 |

### 関連UI変更
- `TaskDetailView`: 完了通知セクション
- `UpdateTaskStatusUseCase`: Handoff自動作成ロジック

---

## 実装順序（TDD）

```
Phase 1: エージェント設定の拡張
├── Feature01: キック設定 ← 最初に実装
└── Feature02: 認証設定

Phase 2: キック機構
└── Feature03: キックトリガー

Phase 3: タスク階層
└── Feature04: 子タスク管理

Phase 4: 完了フロー
└── Feature05: 完了通知
```

---

## テスト実行コマンド

```bash
# 全Featureテスト
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/Feature01_AgentKickSettingsTests \
  -only-testing:AIAgentPMUITests/Feature02_AgentAuthTests \
  -only-testing:AIAgentPMUITests/Feature03_KickTriggerTests \
  -only-testing:AIAgentPMUITests/Feature04_SubtaskTests \
  -only-testing:AIAgentPMUITests/Feature05_CompletionTests

# 個別Feature
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/Feature01_AgentKickSettingsTests
```
