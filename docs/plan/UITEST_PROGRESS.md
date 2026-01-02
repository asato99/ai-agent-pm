# UIテスト実装進捗管理

**作成日**: 2026-01-02
**ステータス**: 🔄 進行中

---

## 概要

UIテストのスキップ解除と実装修正を、TDD（ユニットテストを書きながら）で進行中。

### 現状サマリー（2026-01-02 夕方更新）

| カテゴリ | 総テスト数 | 実行可能 | スキップ | 備考 |
|----------|-----------|----------|----------|------|
| ProjectListTests | 9 | 6 | 3 | コンテキストメニュー等 |
| ProjectListEmptyStateTests | 1 | 1 | 0 | ✅ 完了 |
| TaskBoardTests | 12 | 7 | 5 | D&D、検索等 |
| AgentManagementTests | 15 | 12 | 3 | ✅ 階層構造・並列数追加完了 |
| TaskDetailTests | 13 | 10 | 3 | ✅ 履歴/ハンドオフ/依存関係/コンテキスト完了 |
| CommonNavigationTests | 3 | 3 | 0 | ✅ 完了 |
| CommonAccessibilityTests | 3 | 3 | 0 | ✅ 完了 |
| CommonPerformanceTests | 1 | 1 | 0 | ✅ 完了 |
| DependencyBlockingTests | 4 | 0 | 4 | 🆕 機能未実装（スキップ） |
| ResourceBlockingTests | 4 | 0 | 4 | 🆕 機能未実装（スキップ） |
| AuditTeamTests | 6 | 0 | 6 | 🆕 機能未実装（スキップ） |
| HistoryTests | 4 | 1 | 3 | 🆕 フィルター未実装 |
| ProjectListExtendedTests | 2 | 1 | 1 | 🆕 エージェント割当未実装 |
| **合計** | **77** | **45** | **32** | |

---

## スキップ中テスト一覧（優先度順）

### Priority 1: エージェント管理基盤（AgentManagementTests）✅ 基本完了

サイドバーにAgentsセクション追加済み。基本機能・階層構造・リソース制限実装完了。

| テスト | 機能 | ステータス |
|--------|------|-----------|
| ✅ testAgentManagementAccessible | サイドバーアクセス | 完了 |
| ✅ testAgentListDisplay | エージェント一覧 | 完了 |
| ✅ testNewAgentButtonExists | 作成ボタン | 完了（⇧⌘A） |
| ✅ testAgentStatusIndicators | ステータス表示 | 完了（🟢🟡🟠⚫） |
| ✅ testAgentCardStructure | カード構成 | 完了（AgentRow） |
| ✅ testAgentDetailView | 詳細表示 | 完了 |
| ✅ testAgentCreationFormBasicInfo | 作成フォーム基本 | 完了 |
| ✅ testAgentStatsSection | 統計セクション | 完了 |
| ✅ testAgentEditButton | 編集ボタン | 完了 |
| ✅ testAgentFormTypeSelection | フォームタイプ選択 | 完了 |
| ✅ testAgentFormParentAgentPicker | 親エージェント選択 | **新規追加** |
| ✅ testAgentFormMaxParallelTasks | 並列実行可能数 | **新規追加** |
| ⏳ testAgentCreationWizard3Steps | 3ステップウィザード | 未実装（現在は単一フォーム） |
| ⏳ testAgentActivityHistoryTab | 活動履歴タブ | 未実装 |
| ⏳ testAgentContextMenu | コンテキストメニュー | 未実装 |

### Priority 2: タスク詳細拡張（TaskDetailTests）✅ 基本完了

| テスト | 機能 | ステータス |
|--------|------|-----------|
| ✅ testHistoryEventList | 履歴一覧 | 完了（HistorySection追加） |
| ⏳ testHistoryFilter | 履歴フィルター | 未実装（タイプ別フィルタリング） |
| ✅ testHandoffListDisplay | ハンドオフ一覧 | 完了（HandoffsSection追加） |
| ✅ testDependencyDisplay | 依存関係表示 | 完了（DependenciesSection追加） |
| ✅ testContextAddButton | コンテキスト追加 | 完了（Add Contextボタン + ContextFormView） |
| ~~testSubtaskSection~~ | ~~サブタスク~~ | **要件で不要と定義済み** |
| ⏳ testTaskDetailTabs | タブ形式 | 未実装（現在はスクロール形式） |

### Priority 3: タスクボード拡張（TaskBoardTests）

| テスト | 機能 | 必要な実装 |
|--------|------|-----------|
| testDragAndDropStatusChange | D&Dステータス変更 | onDrop実装 |
| testTaskContextMenu | コンテキストメニュー | 右クリックメニュー |
| testSearchFunction | 検索機能 | SearchField + フィルタリング |
| testFilterBar | フィルターバー | 優先度/担当者フィルター |
| testAgentActivityIndicator | エージェント活動 | リアルタイム活動表示 |

### Priority 4: プロジェクト一覧拡張（ProjectListTests）

| テスト | 機能 | 必要な実装 |
|--------|------|-----------|
| testContextMenuDisplay | コンテキストメニュー | 右クリックメニュー |
| testSortOptions | ソート | 名前/日付/ステータス順 |
| testFilterOptions | フィルター | active/archived切替 |

### Priority 5: ナビゲーション（CommonNavigationTests）

| テスト | 機能 | 必要な実装 |
|--------|------|-----------|
| testKeyboardShortcuts | Cmd+N | 新規プロジェクトショートカット |

---

## 実装アプローチ

### TDD方針

1. **ユニットテスト先行**: 各機能実装前にTests/ディレクトリにテスト追加
2. **UITest解除**: 実装完了後にXCTSkipを削除
3. **対象UITestのみ実行**: 全体実行を避け、変更対象のみテスト

### テスト実行コマンド

```bash
# 特定テストクラスのみ
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/AgentManagementTests

# 特定テストメソッドのみ
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/TaskDetailTests/testHistoryEventList
```

---

## 進捗ログ

### 2026-01-02 (夕方 - 要件カバレッジ完全化)

- [x] 要件カバレッジ分析（全要件ファイル精査）
  - [x] TASKS.md: 依存関係ブロック、リソース可用性ブロック ギャップ特定
  - [x] AGENTS.md: 並列数制限ロジック ギャップ特定
  - [x] AUDIT.md: 監査チーム機能 全て未実装
  - [x] HISTORY.md: 履歴フィルタリング ギャップ特定
- [x] TEST_SCENARIOS.md 新規作成（全テストシナリオ一覧）
- [x] 新規テストクラス5件追加
  - [x] DependencyBlockingTests (4テスト) - 依存関係ブロック
  - [x] ResourceBlockingTests (4テスト) - リソース可用性ブロック
  - [x] AuditTeamTests (6テスト) - 監査チーム機能
  - [x] HistoryTests (4テスト) - 履歴表示・フィルタリング
  - [x] ProjectListExtendedTests (2テスト) - プロジェクト拡張
- [x] ビルド確認・テスト実行確認
  - [x] 全テストコンパイル成功
  - [x] 未実装機能は適切にXCTSkip

### 2026-01-02 (午後 - アサーション精度修正)

- [x] テストシナリオとテスト実装のアサーション精度確認
  - [x] 7件の重大なアサーション問題を特定・修正
  - [x] testColumnHeadersShowTaskCount: カラム件数バッジ検証を追加
  - [x] testTaskCardStructure: 担当者名検証構造を追加
  - [x] testAgentDetailView: AgentDetailView識別子で検証
  - [x] testAgentEditButton: 詳細表示確認を強化
  - [x] testAgentCreationFormTypeSelection: Type/Agent Type検証を追加
  - [x] testStatusChangePicker: Status/Details検証を追加
  - [x] testEditModeScreen: Task Information/Detailsセクション検証を追加
  - [x] 全ての修正テストがパス確認済み

### 2026-01-02 (午後 - 要件整合性確認)

- [x] 要件とテストシナリオの整合性確認
  - [x] TASKS.md, AGENTS.md, PROJECTS.md vs UITest比較
  - [x] blocked状態を正式仕様として採用（TASKS.md更新）
- [x] エージェント階層構造・リソース制限のUI/テスト追加
  - [x] AgentFormViewに「Hierarchy & Resources」セクション追加
  - [x] parentAgentId（親エージェント選択Picker）追加
  - [x] maxParallelTasks（並列実行可能数Stepper）追加
  - [x] testAgentFormParentAgentPicker テスト追加・パス
  - [x] testAgentFormMaxParallelTasks テスト追加・パス
  - [x] XCUITest 12/15テスト合格

### 2026-01-02 (継続)

- [x] Priority 2 (TaskDetailTests) 実装完了
  - [x] TaskDetailViewにHistorySection追加（StateChangeEvent表示）
  - [x] TaskDetailViewにHandoffsSection追加（Handoff履歴表示）
  - [x] TaskDetailViewにDependenciesSection追加（依存タスク表示）
  - [x] ContextFormView新規作成（コンテキスト追加シート）
  - [x] Router.SheetDestinationに.addContext追加
  - [x] HandoffCard, HistoryEventRowコンポーネント追加
  - [x] XCUITest 10/13テスト合格（3スキップ: tabs形式未実装, 履歴フィルター未実装, サブタスク不要）
  - [x] testContextAddButtonのXCUITest検出問題修正（accessibilityIdentifier→ボタンタイトルで検索）

### 2026-01-02

- [x] 状況把握・ドキュメント作成
- [x] Priority 1 (AgentManagement) 基本実装完了
  - [x] ProjectListViewにAgentsセクション追加
  - [x] AgentRowコンポーネント実装（ステータスアイコン🟢🟡🟠⚫、タイプアイコン🤖👤）
  - [x] AgentFormViewにaccessibilityIdentifier追加
  - [x] AIAgentPMAppのメニュー修正（エージェントはプロジェクト非依存）
  - [x] XCUITest 10/13テスト合格
- [x] Priority 2 (TaskDetailTests) 完了
- [ ] Priority 3 (TaskBoardTests) 着手予定

---

## 次のアクション

### フェーズ1: 機能実装（テスト有効化に必要）

1. **依存関係ブロック実装** (P1) 🔴 重要
   - `UpdateTaskStatusUseCase`に依存タスク完了チェック追加
   - UI: ブロックエラー表示アラート
   - テスト有効化: DependencyBlockingTests

2. **リソース可用性ブロック実装** (P1) 🔴 重要
   - `UpdateTaskStatusUseCase`に並列数チェック追加
   - UI: エージェント詳細に現在並列数表示
   - テスト有効化: ResourceBlockingTests

3. **履歴フィルタリング実装** (P2)
   - UI: 履歴セクションにフィルターUI追加
   - テスト有効化: HistoryTests

4. **監査チーム機能実装** (P3)
   - 監査エージェントエンティティ追加
   - ロック/アンロック機能
   - テスト有効化: AuditTeamTests

### フェーズ2: UI機能拡張

5. **TaskBoardTests**
   - ドラッグ&ドロップ実装
   - 検索・フィルター機能
   - コンテキストメニュー

6. **ProjectListTests**
   - コンテキストメニュー
   - ソート・フィルター機能

### 参照ドキュメント

- `docs/test/TEST_SCENARIOS.md` - テストシナリオ一覧
- `docs/requirements/TASKS.md` - タスク仕様（依存関係/リソース制限）
- `docs/requirements/AGENTS.md` - エージェント仕様
- `docs/requirements/AUDIT.md` - 監査チーム仕様
- `docs/requirements/HISTORY.md` - 履歴仕様

---

## 注意事項

- **サブタスク**: 要件（TASKS.md）で「初期実装では不要」と定義。testSubtaskSectionは永続スキップ。
- **blocked状態**: ✅ **採用決定**（TASKS.md更新済み）。依存タスク未完了時に表示。
- **inReview状態**: 削除済み（要件準拠）
- **エージェント階層**: parentAgentId（親エージェント）、maxParallelTasks（並列実行可能数）をフォームに追加済み。

---

## 関連ドキュメント

- [CLAUDE.md](../../CLAUDE.md) - UIテスト実行ルール
- [UITEST_IMPROVEMENT.md](./UITEST_IMPROVEMENT.md) - XCUITest環境問題解決履歴
- [要件: AGENTS.md](../requirements/AGENTS.md)
- [要件: TASKS.md](../requirements/TASKS.md)
- [UI設計: 03_agent_management.md](../ui/03_agent_management.md)
