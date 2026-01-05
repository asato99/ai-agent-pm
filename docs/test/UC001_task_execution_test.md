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

### ⚠️ テスト実装の真の目的

**目的は「テストを通すこと」ではない。目的は「このドキュメント通りにアサートを正確に実装すること」である。**

- テストが失敗した場合、アプリケーションにバグがある可能性がある
- しかし、テストを通すためにアサーションを削除・簡略化・迂回することは**絶対に禁止**
- ドキュメントに記載されたアサーションは全て実装しなければならない
- テストが通らない場合は、アプリケーションを修正するか、ドキュメントの要件を見直す

### 過去の教訓（繰り返し防止）

以下の過ちが繰り返し発生した。二度と繰り返してはならない：

1. **アサーションの簡略化**: 履歴イベント内容確認（`Status Changed`、`todo → in_progress`）のアサーションを「NoHistoryMessageが存在しない」という間接的な確認に置き換えた
2. **目的の履き違え**: 「テストを通すこと」を目的と誤認し、アプリケーションのバグ修正とアサーション簡略化を混同した
3. **ドキュメントの軽視**: ドキュメントに記載された詳細なアサーション要件を確認せずに実装を進めた

**正しいアプローチ**:
1. まずドキュメントを読む
2. ドキュメントの各アサーション要件をテストコードに正確に実装する
3. テストが失敗したら、その原因を調査する（アサーションを変えない）

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
| 1 | Cmd+Shift+T押下 | シートが開く | `XCTAssertTrue(sheet.waitForExistence(timeout: 5))` |
| 2 | TaskTitleFieldにタイトル入力 | フィールドに文字が入る | （入力操作） |
| 3 | Save押下 | シートが閉じる | `XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))` |
| 4 | **リアクティブ確認** | タスクカードが存在する | `XCTAssertTrue(findTaskCard(taskTitle).waitForExistence(timeout: 5))` |
| 5 | タスクカードクリック→詳細確認 | 詳細画面が開く | `XCTAssertTrue(detailView.exists)` |
| 6 | **ステータス確認** | StatusPickerがBacklog | `XCTAssertEqual(statusPicker.value as? String, "Backlog")` |
| 7 | Escape押下 | 詳細画面を閉じる | （操作） |
| 8 | **カラム所属確認** | タスクがBacklogカラム内にある | `XCTAssertTrue(taskExistsInColumn(taskTitle, "TaskColumn_backlog"))` |
| 9 | **他カラム不在確認** | タスクがTo Doカラムにない | `XCTAssertFalse(taskExistsInColumn(taskTitle, "TaskColumn_todo"))` |

**技術メモ**: `findTaskCard()`は`app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title))`を使用

#### Step 3-2: エージェント割当（編集フォーム経由）

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | タスクカードクリック | 詳細画面が開く | `XCTAssertTrue(detailView.waitForExistence(timeout: 5))` |
| 2 | **割当前確認** | TaskAssigneeにエージェント名がない | `XCTAssertFalse(detailView.staticTexts[agentName].exists)` |
| 3 | Cmd+E押下（編集フォーム） | 編集シートが開く | `XCTAssertTrue(editSheet.waitForExistence(timeout: 5))` |
| 4 | TaskAssigneePicker確認 | ピッカーが存在する | `XCTAssertTrue(assigneePicker.exists)` |
| 5 | TaskAssigneePickerクリック | メニューが表示される | （操作） |
| 6 | エージェント名選択 | メニュー項目をクリック | `XCTAssertTrue(menuItem[agentName].exists); menuItem.click()` |
| 7 | Save押下 | 編集シートが閉じる | `XCTAssertTrue(editSheet.waitForNonExistence(timeout: 5))` |
| 8 | **リアクティブ確認** | 詳細ビューにエージェント名が表示 | `XCTAssertTrue(detailView.staticTexts[agentName].waitForExistence(timeout: 3))` |
| 9 | **タスクカードにも反映確認** | カードのラベルにエージェント名含む | `XCTAssertTrue(findTaskCard(taskTitle).label.contains(agentName))` |

#### Step 3-3: backlog → todo

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | **変更前確認** | StatusPickerの値がBacklog | `XCTAssertEqual(statusPicker.value as? String, "Backlog")` |
| 2 | StatusPickerクリック | メニューが表示される | `statusPicker.click()` |
| 3 | "To Do"メニュー項目選択 | 選択される | `menuItems["To Do"].click()` |
| 4 | **ステータス更新確認** | StatusPickerの値がTo Do | `XCTAssertEqual(statusPicker.value as? String, "To Do")` |
| 5 | 詳細画面を閉じてリフレッシュ | UIリフレッシュ | `app.typeKey(.escape); app.typeKey("r", modifiers: .command)` |
| 6 | **カラム移動確認** | タスクがTo Doカラム内にある | `XCTAssertTrue(taskExistsInColumn(taskTitle, "TaskColumn_todo"))` |
| 7 | **前カラム不在確認** | タスクがBacklogカラムから消えている | `XCTAssertFalse(taskExistsInColumn(taskTitle, "TaskColumn_backlog"))` |

#### Step 3-4: todo → in_progress（キック実行）

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | **変更前確認** | ステータスがTo Do | `XCTAssertEqual(statusPicker.value as? String, "To Do")` |
| 2 | StatusPicker開く | ピッカーが表示される | `statusPicker.click()` |
| 3 | In Progress選択 | 選択される | `menuItems["In Progress"].click()` |
| 4 | **ステータス更新確認** | 詳細ビューのステータスがIn Progress | `XCTAssertEqual(statusPicker.value as? String, "In Progress")` |
| 5 | 詳細画面を閉じてリフレッシュ | データ更新を待機 | `app.typeKey(.escape); app.typeKey("r", modifiers: .command)` |
| 6 | **カラム移動確認** | タスクがIn Progressカラム内に存在 | `XCTAssertTrue(taskExistsInColumn(taskTitle, "TaskColumn_in_progress"))` |
| 7 | **前カラム不在確認** | タスクがTo Doカラムから消えている | `XCTAssertFalse(taskExistsInColumn(taskTitle, "TaskColumn_todo"))` |
| 8 | タスク詳細を再度開く | 詳細画面が開く | `findTaskCard(taskTitle).click()` |
| 9 | **履歴セクション確認** | HistorySectionが存在する | `XCTAssertTrue(historySection.waitForExistence(timeout: 3))` |
| 10 | **履歴空でない確認** | 「No history events」が表示されていない | `XCTAssertFalse(noHistoryMessage.exists)` |
| 11 | **履歴イベント内容確認** | Status Changedイベントが記録されている | `XCTAssertTrue(historySection.staticTexts["Status Changed"].exists)` |
| 12 | **履歴遷移内容確認** | 「todo → in_progress」の遷移が記録 | `XCTAssertTrue(historySection.staticTexts["todo → in_progress"].exists)` |

**注意**:
- 履歴確認はハードアサーション必須。`if historySection.exists`のような条件分岐は禁止
- ステータス変更時は`statusChanged`イベント（displayName: "Status Changed"）が作成される
- 遷移内容は`previousState → newState`形式で表示される

#### Step 3-5: in_progress → done

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | **変更前確認** | StatusPickerの値がIn Progress | `XCTAssertEqual(statusPicker.value as? String, "In Progress")` |
| 2 | StatusPickerクリック | メニューが表示される | `statusPicker.click()` |
| 3 | "Done"メニュー項目選択 | 選択される | `menuItems["Done"].click()` |
| 4 | **ステータス更新確認** | StatusPickerの値がDone | `XCTAssertEqual(statusPicker.value as? String, "Done")` |
| 5 | 詳細画面を閉じてリフレッシュ | UIリフレッシュ | `app.typeKey(.escape); app.typeKey("r", modifiers: .command)` |
| 6 | **カラム移動確認** | タスクがDoneカラム内にある | `XCTAssertTrue(taskExistsInColumn(taskTitle, "TaskColumn_done"))` |
| 7 | **前カラム不在確認** | タスクがIn Progressカラムから消えている | `XCTAssertFalse(taskExistsInColumn(taskTitle, "TaskColumn_in_progress"))` |

---

### Phase 4: 依存関係ブロック検証

**シナリオID**: TS-UC001-P4
**関連シナリオ**: TS-DEP-001, TS-DEP-004

**目的**: 依存タスク未完了時にin_progressへの遷移がブロックされることを確認

**前提条件**:
- task_dep_childがtask_dep_parentに依存
- task_dep_parentがdone以外のステータス
- task_dep_childがtodo（またはbacklog）ステータス
- シードデータタイトル: 「依存タスク」

**検証項目**:

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | Cmd+Shift+D押下で依存タスク選択 | 詳細画面が開く | `XCTAssertTrue(detailView.waitForExistence(timeout: 5))` |
| 2 | **変更前ステータス確認** | StatusPickerの値がTo Do（またはBacklog） | `XCTAssertTrue(["To Do", "Backlog"].contains(statusPicker.value as? String ?? ""))` |
| 3 | DependenciesSectionを確認 | 依存関係セクションが存在 | `XCTAssertTrue(dependenciesSection.waitForExistence(timeout: 3))` |
| 4 | StatusPickerクリック | メニューが表示される | `statusPicker.click()` |
| 5 | "In Progress"メニュー項目選択 | ブロックエラーが発生 | `menuItems["In Progress"].click()` |
| 6 | **エラーアラート表示確認** | エラーシートが表示される | `XCTAssertTrue(alertSheet.waitForExistence(timeout: 3))` |
| 7 | OKボタン押下でアラートを閉じる | アラートが閉じる | `XCTAssertTrue(alertSheet.waitForNonExistence(timeout: 3))` |
| 8 | **ステータス未変更確認** | StatusPickerの値がIn Progressでない | `XCTAssertNotEqual(statusPicker.value as? String, "In Progress")` |
| 9 | Escape押下で詳細画面を閉じる | 詳細画面が閉じる | （操作） |
| 10 | **タスクカード存在確認** | タスクカードがボードに存在 | `XCTAssertTrue(findTaskCard(childTaskTitle).exists)` |

**失敗条件**: エラーアラートが表示されない、またはステータスがIn Progressに変更された場合、即座に失敗

---

### Phase 5: リソース制限ブロック検証

**シナリオID**: TS-UC001-P5
**関連シナリオ**: TS-RES-001, TS-RES-004

**目的**: エージェントの並列実行上限到達時にin_progressへの遷移がブロックされることを確認

**前提条件**:
- agent_backendのmaxParallelTasks=1
- task_resource_blockerがin_progressでagent_backendにアサイン済み（上限到達）
- task_resource_testがtodoでagent_backendにアサイン済み
- シードデータタイトル: 「追加開発タスク」（AIAgentPMApp.swift参照）

**検証項目**:

| # | 操作 | 期待結果 | アサーション |
|---|------|----------|--------------|
| 1 | Cmd+Shift+G押下でリソーステストタスク選択 | 詳細画面が開く | `XCTAssertTrue(detailView.waitForExistence(timeout: 5))` |
| 2 | **変更前ステータス確認** | StatusPickerの値がTo Do | `XCTAssertEqual(statusPicker.value as? String, "To Do")` |
| 3 | 担当エージェント確認 | 詳細ビューにbackend-devが表示 | `XCTAssertTrue(detailView.staticTexts["backend-dev"].exists)` |
| 4 | StatusPickerクリック | メニューが表示される | `statusPicker.click()` |
| 5 | "In Progress"メニュー項目選択 | ブロックエラーが発生 | `menuItems["In Progress"].click()` |
| 6 | **エラーアラート表示確認** | エラーシートが表示される | `XCTAssertTrue(alertSheet.waitForExistence(timeout: 3))` |
| 7 | OKボタン押下でアラートを閉じる | アラートが閉じる | `XCTAssertTrue(alertSheet.waitForNonExistence(timeout: 3))` |
| 8 | **ステータス未変更確認** | StatusPickerの値がTo Doのまま | `XCTAssertEqual(statusPicker.value as? String, "To Do")` |
| 9 | Escape押下で詳細画面を閉じる | 詳細画面が閉じる | （操作） |
| 10 | **タスクカード存在確認** | タスクカードがボードに存在 | `XCTAssertTrue(findTaskCard(resourceTestTitle).exists)` |

**失敗条件**: エラーアラートが表示されない、またはステータスがIn Progressに変更された場合、即座に失敗

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

**参照**: `Sources/App/AIAgentPMApp.swift` の `seedBasicUITestData()` メソッド

```swift
// 1. 依存関係テスト用（AIAgentPMApp.swift 実装）
let prerequisiteTask = Task(
    id: TaskID(value: "uitest_prerequisite_task"),
    title: "前提タスク",           // ← 実際のタイトル
    status: .backlog,              // backlog（未完了）
    projectId: project.id
)

let dependentTask = Task(
    id: TaskID(value: "uitest_dependent_task"),
    title: "依存タスク",           // ← 実際のタイトル（Cmd+Shift+D で選択）
    status: .backlog,
    projectId: project.id,
    dependencies: [prerequisiteTaskId]  // prerequisiteTaskに依存
)

// 2. リソース制限テスト用（AIAgentPMApp.swift 実装）
let devAgent = Agent(
    id: AgentID(value: "uitest_backend_dev"),
    name: "backend-dev",
    maxParallelTasks: 1  // 並列1に制限
)

// 既にin_progressのタスク（枠を消費）
let apiImplementTask = Task(
    id: TaskID(value: "uitest_api_implement"),
    title: "API実装",
    status: .inProgress,          // 既にin_progress
    assigneeId: devAgent.id
)

// リソース制限テスト対象タスク
let resourceTestTask = Task(
    id: TaskID(value: "uitest_resource_task"),
    title: "追加開発タスク",       // ← 実際のタイトル（Cmd+Shift+G で選択）
    status: .todo,
    assigneeId: devAgent.id        // devAgentにアサイン済み
)
```

### テスト用キーボードショートカット

| ショートカット | 対象タスク | 用途 |
|---------------|-----------|------|
| Cmd+Shift+D | 依存タスク（uitest_dependent_task） | 依存関係ブロックテスト |
| Cmd+Shift+G | 追加開発タスク（uitest_resource_task） | リソース制限ブロックテスト |

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
| 2026-01-05 | アサーション強化: 全フェーズに状態変化の包括的アサーションを追加 |
| 2026-01-05 | アサーション修正: XCUITest APIに合わせた正確なアサーション記述に修正 |
| 2026-01-05 | 目的明確化: テスト実装の真の目的と過去の教訓を追加 |

### 2026-01-05 アサーション修正の詳細

**修正内容**:

1. **StatusPicker値確認**: `statusLabel.staticTexts["Backlog"]`から`statusPicker.value as? String`に修正
2. **履歴イベント確認**: `"started"`から`"Status Changed"`に修正（実際のdisplayName）
3. **履歴遷移確認**: `"todo → in_progress"`形式の遷移記録確認を追加
4. **カラム所属確認**: `column.descendants.staticTexts`から`taskExistsInColumn()`ヘルパー関数に修正
5. **シードデータ参照**: AIAgentPMApp.swiftの実際のデータに合わせて更新
6. **タスクタイトル修正**: Phase 5の「リソーステスト」→「追加開発タスク」

**XCUITest技術メモ**:
- `popUpButton.value`でPopUpButtonの現在値を取得
- TaskCardButtonは`.accessibilityElement(children: .combine)`を使用するためdescendants検索不可
- `NSPredicate(format: "label CONTAINS %@", title)`でタスクカード検索

### 2026-01-05 アサーション強化の詳細

**追加されたアサーションカテゴリ**:

1. **カラム所属確認**: タスクが正しいカラム内に存在することを確認
2. **他カラム不在確認**: タスクが移動前のカラムに存在しないことを確認
3. **変更前確認**: 操作前の状態を明示的に確認
4. **ステータス更新確認**: 詳細ビューのステータス表示が更新されていることを確認
5. **割当前後確認**: Assignee変更前後の状態を確認
6. **履歴イベント内容確認**: Status Changedイベントと遷移内容の確認

**設計理由**:
- 「テストが通ったが実際には動いていない」問題を防止
- UIのリアクティブな更新を確実に検証
- ブロック時の「何も変わらない」状態を明示的にアサート
