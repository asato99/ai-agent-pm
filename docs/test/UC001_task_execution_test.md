# UC001: エージェントによるタスク実行 テストシナリオ

**対応ユースケース**: `docs/usecase/UC001_TaskExecutionByAgent.md`
**テストクラス**: `UC001_TaskExecutionByAgentTests`
**最終更新**: 2026-01-05

---

## 設計原則

### E2Eテストの必須ルール

1. **単一テストメソッド**: 1回のアプリ起動で全フローを検証（複数メソッド分割禁止）
2. **リアクティブ検証**: 全ての「操作→UI反映」をアサート（スキップ禁止）
3. **ハードアサーション**: `if`による条件分岐禁止、`XCTAssertTrue`で必ず失敗させる
4. **前提条件の明示**: テストデータ（シードデータ）の要件を明確に定義

### テスト失敗時の原則

- 要素が見つからない → **テスト失敗**（スキップではない）
- UI更新が反映されない → **テスト失敗**（スキップではない）
- ブロックが発生しない → **テスト失敗**（成功扱いにしない）

---

## 必須シードデータ

| ID | 種別 | 条件 | 用途 |
|----|------|------|------|
| project_test | Project | 名前「テストプロジェクト」 | E2Eテスト対象 |
| agent_backend | Agent | 名前「backend-dev」、maxParallelTasks=1 | リソース制限テスト用 |
| task_dep_parent | Task | status=backlog、依存なし | 依存関係テストの親 |
| task_dep_child | Task | status=backlog、task_dep_parentに依存 | 依存関係テストの子 |
| task_resource_blocker | Task | status=in_progress、agent_backendにアサイン | リソース制限発動用 |
| task_resource_test | Task | status=todo、agent_backendにアサイン | リソース制限検証用 |

---

## テストフロー（単一メソッド内で全て実行）

```
testE2E_UC001_CompleteWorkflow()
├── Phase 1: カンバンボード構造確認
├── Phase 2: タスク作成バリデーション
├── Phase 3: タスク完全ライフサイクル
│   ├── Step 3-1: タスク作成 → Backlog表示
│   ├── Step 3-2: エージェント割当 → 割当表示
│   ├── Step 3-3: backlog → todo → カラム移動
│   ├── Step 3-4: todo → in_progress → カラム移動 + History記録
│   └── Step 3-5: in_progress → done → カラム移動
├── Phase 4: 依存関係ブロック検証
│   ├── Step 4-1: 依存タスク選択
│   ├── Step 4-2: in_progress変更試行
│   └── Step 4-3: エラーアラート表示確認
└── Phase 5: リソース制限ブロック検証
    ├── Step 5-1: リソース制限対象タスク選択
    ├── Step 5-2: in_progress変更試行
    └── Step 5-3: エラーアラート表示確認
```

---

## 詳細テストシナリオ

### Phase 1: カンバンボード構造確認

**シナリオID**: TS-UC001-P1

**目的**: タスクボードに5つのカラムが正しい順序で表示されることを確認

**前提条件**:
- アプリが起動している
- 「テストプロジェクト」を選択済み

**検証項目**:

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | TaskBoard表示確認 | TaskBoard識別子が存在する | `XCTAssertTrue(taskBoard.exists)` |
| 2 | Backlogカラム確認 | TaskColumn_backlogが存在する | `XCTAssertTrue(column.exists)` |
| 3 | To Doカラム確認 | TaskColumn_todoが存在する | `XCTAssertTrue(column.exists)` |
| 4 | In Progressカラム確認 | TaskColumn_in_progressが存在する | `XCTAssertTrue(column.exists)` |
| 5 | Blockedカラム確認 | TaskColumn_blockedが存在する | `XCTAssertTrue(column.exists)` |
| 6 | Doneカラム確認 | TaskColumn_doneが存在する | `XCTAssertTrue(column.exists)` |

**失敗条件**: いずれかのカラムが存在しない場合、即座に失敗

---

### Phase 2: タスク作成バリデーション

**シナリオID**: TS-UC001-P2

**目的**: 空タイトルでタスク作成できないことを確認

**検証項目**:

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | Cmd+Shift+T押下 | 新規タスクシートが開く | `XCTAssertTrue(sheet.exists)` |
| 2 | タイトル未入力状態確認 | Saveボタンが無効 | `XCTAssertFalse(saveButton.isEnabled)` |
| 3 | シートキャンセル | シートが閉じる | `XCTAssertTrue(sheet.waitForNonExistence)` |

**失敗条件**: 空タイトルでSaveボタンが有効な場合、即座に失敗

---

### Phase 3: タスク完全ライフサイクル

**シナリオID**: TS-UC001-P3

**目的**: タスク作成から完了までの全ステータス遷移を確認

#### Step 3-1: タスク作成

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | Cmd+Shift+T押下 | シートが開く | `XCTAssertTrue(sheet.exists)` |
| 2 | タイトル入力 | フィールドに文字が入る | （入力操作） |
| 3 | Save押下 | シートが閉じる | `XCTAssertTrue(sheet.waitForNonExistence)` |
| 4 | **リアクティブ確認** | タスクカードがBacklogカラムに表示される | `XCTAssertTrue(taskCard.exists)` |

#### Step 3-2: エージェント割当

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | タスクカードクリック | 詳細画面が開く | `XCTAssertTrue(detailView.exists)` |
| 2 | AssigneePicker開く | ピッカーが表示される | `XCTAssertTrue(picker.exists)` |
| 3 | エージェント選択 | 選択肢が表示される | `XCTAssertTrue(option.exists)` |
| 4 | **リアクティブ確認** | 割当が反映される | `XCTAssertTrue(updatedAssignee.exists)` |

#### Step 3-3: backlog → todo

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | StatusPicker開く | ピッカーが表示される | `XCTAssertTrue(picker.exists)` |
| 2 | To Do選択 | 選択される | （選択操作） |
| 3 | **リアクティブ確認** | タスクがTo Doカラムに移動 | `XCTAssertTrue(taskInTodoColumn.exists)` |

#### Step 3-4: todo → in_progress

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | StatusPicker開く | ピッカーが表示される | `XCTAssertTrue(picker.exists)` |
| 2 | In Progress選択 | 選択される | （選択操作） |
| 3 | **リアクティブ確認** | タスクがIn Progressカラムに移動 | `XCTAssertTrue(taskInProgressColumn.exists)` |
| 4 | **履歴確認** | HistorySectionにイベント記録 | `XCTAssertTrue(historyEvent.exists)` |

#### Step 3-5: in_progress → done

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | StatusPicker開く | ピッカーが表示される | `XCTAssertTrue(picker.exists)` |
| 2 | Done選択 | 選択される | （選択操作） |
| 3 | **リアクティブ確認** | タスクがDoneカラムに移動 | `XCTAssertTrue(taskInDoneColumn.exists)` |

---

### Phase 4: 依存関係ブロック検証

**シナリオID**: TS-UC001-P4
**関連シナリオ**: TS-DEP-001, TS-DEP-004

**目的**: 依存タスク未完了時にin_progressへの遷移がブロックされることを確認

**前提条件**:
- task_dep_childがtask_dep_parentに依存
- task_dep_parentがdone以外のステータス

**検証項目**:

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | 依存タスク(task_dep_child)を選択 | 詳細画面が開く | `XCTAssertTrue(detailView.exists)` |
| 2 | DependenciesSectionを確認 | 依存関係が表示される | `XCTAssertTrue(dependenciesSection.exists)` |
| 3 | StatusPickerでIn Progress選択 | ブロックエラーが発生 | `XCTAssertTrue(errorAlert.exists)` |
| 4 | エラーメッセージ確認 | 依存関係エラーメッセージが含まれる | `XCTAssertTrue(alertMessage.contains("依存"))` |
| 5 | **ステータス未変更確認** | タスクがtodoのまま | `XCTAssertEqual(currentStatus, "todo")` |

**失敗条件**: エラーアラートが表示されない、またはステータスが変更された場合、即座に失敗

---

### Phase 5: リソース制限ブロック検証

**シナリオID**: TS-UC001-P5
**関連シナリオ**: TS-RES-001, TS-RES-004

**目的**: エージェントの並列実行上限到達時にin_progressへの遷移がブロックされることを確認

**前提条件**:
- agent_backendのmaxParallelTasks=1
- task_resource_blockerがin_progressでagent_backendにアサイン済み（上限到達）
- task_resource_testがtodoでagent_backendにアサイン済み

**検証項目**:

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | リソーステストタスク(task_resource_test)を選択 | 詳細画面が開く | `XCTAssertTrue(detailView.exists)` |
| 2 | 担当エージェント確認 | agent_backendがアサインされている | `XCTAssertEqual(assignee, "backend-dev")` |
| 3 | StatusPickerでIn Progress選択 | ブロックエラーが発生 | `XCTAssertTrue(errorAlert.exists)` |
| 4 | エラーメッセージ確認 | リソース制限エラーメッセージが含まれる | `XCTAssertTrue(alertMessage.contains("並列") OR alertMessage.contains("リソース"))` |
| 5 | **ステータス未変更確認** | タスクがtodoのまま | `XCTAssertEqual(currentStatus, "todo")` |

**失敗条件**: エラーアラートが表示されない、またはステータスが変更された場合、即座に失敗

---

## アサーション方針

### 禁止パターン

```swift
// ❌ 禁止: 条件分岐によるスキップ
if element.exists {
    // テスト実行
} else {
    print("⚠️ スキップ")  // これは許容されない
}

// ❌ 禁止: waitForExistence失敗時のスキップ
if element.waitForExistence(timeout: 3) {
    // 続行
} else {
    print("見つからなかったのでスキップ")  // これは許容されない
}
```

### 必須パターン

```swift
// ✅ 正しい: ハードアサーション
XCTAssertTrue(element.waitForExistence(timeout: 5),
              "❌ REACTIVE: 要素が見つからない - \(elementDescription)")

// ✅ 正しい: guard + throw
guard element.waitForExistence(timeout: 5) else {
    XCTFail("❌ 前提条件未達成: \(elementDescription)")
    throw TestError.failedPrecondition("要素が存在しない")
}

// ✅ 正しい: エラーアラート必須確認
let errorAlert = app.sheets.firstMatch
XCTAssertTrue(errorAlert.waitForExistence(timeout: 3),
              "❌ BLOCKING: ブロックエラーが表示されるべき")
```

---

## シードデータ要件

### UITestScenario.basic に必要なデータ

```swift
// BasicTestDataSeeder.swift で定義すべきデータ

// 1. 依存関係テスト用
let parentTask = Task(
    id: "task_dep_parent",
    title: "依存関係テスト親タスク",
    status: .backlog,
    projectId: "project_test"
)

let childTask = Task(
    id: "task_dep_child",
    title: "依存関係テスト子タスク",
    status: .backlog,
    projectId: "project_test",
    dependencies: ["task_dep_parent"]  // 親に依存
)

// 2. リソース制限テスト用
let agent = Agent(
    id: "agent_backend",
    name: "backend-dev",
    maxParallelTasks: 1  // 並列1に制限
)

let blockerTask = Task(
    id: "task_resource_blocker",
    title: "リソースブロッカー",
    status: .inProgress,  // 既にin_progress（枠を消費）
    assigneeId: "agent_backend"
)

let resourceTestTask = Task(
    id: "task_resource_test",
    title: "リソーステスト対象",
    status: .todo,
    assigneeId: "agent_backend"  // 同じエージェント
)
```

---

## 関連シナリオマッピング

| UC001 Phase | TEST_SCENARIOS.md ID | 説明 |
|-------------|---------------------|------|
| Phase 1 | TS-02-001 | カンバンカラム構造確認 |
| Phase 2 | TS-02-003 | 新規タスク作成ボタン |
| Phase 3 | TS-04-008 | ステータス変更ピッカー |
| Phase 4 | TS-DEP-001, TS-DEP-004 | 依存関係ブロック |
| Phase 5 | TS-RES-001, TS-RES-004 | リソース制限ブロック |

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-05 | 初版作成: E2Eテスト設計原則とアサーション方針を明確化 |
