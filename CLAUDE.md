# AI Agent PM - Claude Code ガイドライン

このファイルはClaude Codeがプロジェクト固有のルールを遵守するためのガイドラインです。

---

## UIテスト実行ルール

### 原則: 対象テストのみ実行

UIテストは全体実行に**約6分以上**かかるため、**修正対象のテストクラス/メソッドのみ**を実行してください。

### 実行コマンド

```bash
# 特定のテストクラスのみ実行
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/TaskBoardTests

# 特定のテストメソッドのみ実行
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/TaskBoardTests/testKanbanColumnsStructure

# 複数のテストを指定
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/TaskBoardTests \
  -only-testing:AIAgentPMUITests/TaskDetailTests
```

### 全体実行が必要なケース

以下の場合のみ全体実行を検討:
- リリース前の最終確認
- 大規模リファクタリング後
- テスト基盤の変更後
- ユーザーから明示的に全体実行を依頼された場合

### テストクラス一覧

| クラス名 | 対象画面 |
|----------|----------|
| `ProjectListTests` | プロジェクト一覧 |
| `ProjectListEmptyStateTests` | 空状態表示 |
| `TaskBoardTests` | タスクボード |
| `TaskDetailTests` | タスク詳細 |
| `AgentManagementTests` | エージェント管理 |
| `CommonNavigationTests` | ナビゲーション |
| `CommonAccessibilityTests` | アクセシビリティ |
| `CommonPerformanceTests` | パフォーマンス |

---

## 要件ファイルの参照

実装・テスト修正時は必ず要件を確認:

| ドメイン | ファイル |
|----------|----------|
| タスク | `docs/requirements/TASKS.md` |
| エージェント | `docs/requirements/AGENTS.md` |
| プロジェクト | `docs/requirements/PROJECTS.md` |
| UI修正点 | `docs/requirements/UI_MODIFICATIONS.md` |
| 監査チーム | `docs/requirements/AUDIT.md` |
| 履歴 | `docs/requirements/HISTORY.md` |

---

## ステータス定義

### TaskStatus（要件準拠）

```
backlog → todo → in_progress → done
                      ↓
                  cancelled
```

- `inReview` は**削除済み**
- `blocked` は**検討中**（現実装では明示的カラムとして存在）

### AgentStatus

```
active / inactive / busy
```

### ProjectStatus

```
active / archived
```

- `completed` は**削除済み**

---

## UIテスト設計原則

### リアクティブ要件

**原則**: UIは状態変更に自動的に反応して更新されるべき（リアクティブ）

テストコード内で**リフレッシュ操作（⌘R）を行う必要がある場合は、リアクティブ要件違反**として扱います。

```swift
// ❌ リアクティブ要件違反の疑い
statusPicker.click()
app.menuItems["Done"].click()
app.typeKey("r", modifierFlags: .command)  // ← リフレッシュが必要 = 要件違反
XCTAssertTrue(taskExistsInColumn(...))

// ✅ 正しいリアクティブ実装
statusPicker.click()
app.menuItems["Done"].click()
Thread.sleep(forTimeInterval: 0.5)  // UI更新待機のみ
XCTAssertTrue(taskExistsInColumn(...))  // 自動的に反映されている
```

**例外**: どうしてもリアクティブが技術的に困難な場合は、実装ファイルに理由をコメントで明記すること。

---

## 設計方針

- **サブタスク**: 初期実装では不要（依存関係のみでタスク間関係を表現）
- **エージェント**: プロジェクト非依存のトップレベルエンティティ
- **依存関係**: DAG構造、循環依存禁止

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2025-01-02 | 初版作成: UIテスト実行ルール、要件参照を記載 |
| 2026-01-06 | リアクティブ要件追加: テストでのリフレッシュ操作は要件違反として扱う |
