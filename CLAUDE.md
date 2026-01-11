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

## デバッグ原則

### 基本方針: ログで確認してから判断する

機能が期待通りに動作しない場合、**ツールや外部要因のせいにする前に**、必ず以下を実施すること：

1. **ログを追加して実際の動作を確認する**
   - 推測ではなく事実に基づいて問題を特定する

2. **実装の問題を真剣に検討する**
   - 外部ツールの問題と結論づける前に、実装側の問題を徹底的に調査
   - 「XCUITestの制限」「SwiftUIのバグ」などと決めつけない

3. **外部要因を主張する場合は論拠を示す**
   - 公式ドキュメント、既知のバグレポート、再現可能な最小例など
   - 根拠なく外部要因のせいにしない

---

## ログ取得ベストプラクティス

**詳細ガイド**: [`docs/guide/LOGGING.md`](docs/guide/LOGGING.md)

### 要点

- **XCUITest環境**: `NSLog`/`print`はキャプチャされないため、**ファイルベースログ**を使用
- **本番コード**: `OSLog` または `swift-log` を使用
- **デバッグの鉄則**: 確実に呼ばれるコード（クリック等）にもログを追加し、ログ出力自体が機能していることを確認してから問題を切り分ける

```bash
# XCUITestデバッグ時のログ確認
rm -f /tmp/app_debug.log  # テスト前にクリア
# テスト実行後
cat /tmp/app_debug.log
```

---

## 修正済みの問題

### ドラッグ＆ドロップ機能（2026-01-11修正）

**原因**: `Button`と`onDrag`のジェスチャー競合
**修正**: `onTapGesture` + `draggable` + `dropDestination`に変更
**検証**: 手動テスト✅、UIテスト✅

**詳細**: [`docs/retrospective/2026-01-11_DragAndDrop_XCUITest.md`](docs/retrospective/2026-01-11_DragAndDrop_XCUITest.md)

### XCUITestの制限: LazyVStack内の要素検出

`LazyVStack`内の要素はXCUITestのアクセシビリティ階層に正しく公開されない場合がある。

**対応**:
- 要素のframe座標を使用した検出は避ける
- accessibilityIdentifierで直接検索する
- 必要に応じてDB検証にフォールバック

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
| 2026-01-06 | ログ取得ベストプラクティス追加: 詳細は`docs/guide/LOGGING.md`に分離 |
| 2026-01-11 | ドラッグ＆ドロップ機能修正: Button+onDrag競合を解消 |
