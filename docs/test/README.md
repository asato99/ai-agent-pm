# UIテストシナリオ

このディレクトリには、PRD UI仕様書に基づくUIテストシナリオを記載しています。

## ディレクトリ構成

```
docs/test/
├── README.md                      # 本ファイル
├── 01_project_list_test.md        # プロジェクト一覧画面
├── 02_task_board_test.md          # タスクボード画面
├── 03_agent_management_test.md    # エージェント管理画面
├── 04_task_detail_test.md         # タスク詳細画面
├── 05_common_test.md              # 共通テスト（ナビゲーション、アクセシビリティ等）
├── 07_audit_team_test.md          # 監査チーム管理画面
└── 08_history_test.md             # 履歴・タイムライン画面
```

## テスト実行環境

| 項目 | 内容 |
|------|------|
| テストフレームワーク | XCUITest |
| プロジェクト生成 | xcodegen |
| 対象プラットフォーム | macOS 14.0+ |
| テストファイル | `UITests/AIAgentPMUITests.swift` |

## テスト実行コマンド

### 対象テストのみ実行（推奨）

UIテストは全体実行に**約6分以上**かかるため、**修正対象のテストクラス/メソッドのみ**を実行してください。

```bash
# 特定のテストクラスのみ実行（推奨）
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

### テストクラス一覧

| クラス名 | 対象画面 | 実行引数 |
|----------|----------|----------|
| `ProjectListTests` | プロジェクト一覧 | `-only-testing:AIAgentPMUITests/ProjectListTests` |
| `ProjectListEmptyStateTests` | 空状態 | `-only-testing:AIAgentPMUITests/ProjectListEmptyStateTests` |
| `TaskBoardTests` | タスクボード | `-only-testing:AIAgentPMUITests/TaskBoardTests` |
| `TaskDetailTests` | タスク詳細 | `-only-testing:AIAgentPMUITests/TaskDetailTests` |
| `AgentManagementTests` | エージェント管理 | `-only-testing:AIAgentPMUITests/AgentManagementTests` |
| `CommonNavigationTests` | ナビゲーション | `-only-testing:AIAgentPMUITests/CommonNavigationTests` |
| `CommonAccessibilityTests` | アクセシビリティ | `-only-testing:AIAgentPMUITests/CommonAccessibilityTests` |
| `CommonPerformanceTests` | パフォーマンス | `-only-testing:AIAgentPMUITests/CommonPerformanceTests` |

### 全体実行（特別な場合のみ）

以下の場合のみ全体実行:
- リリース前の最終確認
- 大規模リファクタリング後
- テスト基盤の変更後

```bash
# Xcodeプロジェクト生成
xcodegen generate

# UIテスト全体実行（時間がかかるため注意）
xcodebuild -project AIAgentPM.xcodeproj -scheme AIAgentPM -destination 'platform=macOS' test
```

> **⚠️ 重要: macOS SwiftUI + XCUITest の制限事項**
>
> XCUITestはターミナル/CI環境からの実行時にSwiftUIのウィンドウを検出できません。
> テストは **Xcode GUI環境から実行する必要があります**。
> 詳細は下記「macOS XCUITest 制限事項」セクションを参照してください。

## macOS XCUITest 制限事項

### 問題概要

macOS SwiftUI アプリケーションに対する XCUITest は、ターミナルやCI環境からの `xcodebuild test` コマンドでは正常に動作しません。

**症状:**
- アプリは起動する（PID取得可能、メニューバー表示）
- しかし `app.windows.count` が 0 を返す
- 全ての UI 要素（ボタン、テキスト等）が検出不可

**原因:**
XCUITest のアクセシビリティ階層へのアクセスには、macOS の GUI 環境（WindowServer への接続）が必要です。ターミナルセッションや SSH 経由での実行では、この接続が確立されません。

### 解決方法

| 方法 | 説明 |
|------|------|
| **Xcode GUI から実行** | Product → Test (⌘U) で実行 ✅推奨 |
| **Xcode Server / Cloud** | CI用のmacOS環境でGUIセッションを提供 |
| **Screen Sharing有効化** | ヘッドレス環境でもGUIセッションを維持 |

### CI環境での対応

CI環境でUIテストを実行する場合は、以下のいずれかを検討:

1. **Self-hosted macOS Runner**: GUI セッションを持つmacOSマシンを使用
2. **Xcode Cloud**: Apple の CI サービス（GUI環境を自動提供）
3. **UIテストをスキップ**: `xcodebuild test -skip-testing:AIAgentPMUITests`

### 調査ログ（2024-12-31）

```
Windows: 0
Groups: 0
SplitGroups: 0
ScrollViews: 0
StaticTexts: 0
Buttons: 0
ProjectList exists: false
```

アプリは正常に起動（PIDあり）するが、XCUITestがUIツリーにアクセスできない状態。

## 進捗サマリ

**最終更新**: 2024-12-31 (第2回更新)

### 実装状況

| 状態 | 記号 | 説明 |
|------|------|------|
| 実装済み | ✅ | 具体的なUI要素を検証するアサーションが実装されている |
| スタブ | 🔸 | テストメソッドは存在するが `assertWindowExists()` のみ |
| 未実装 | ⏳ | テストメソッドが存在しない |

### テスト実行結果

**49テスト中48テストがパス** (2024-12-31)

- 1件の失敗は環境問題（ゾンビプロセス）によるもの
- テストコード自体は正常に動作

### 画面別進捗

| 画面 | テストクラス | 総シナリオ | ✅実装 | 🔸スタブ | ⏳未実装 |
|------|-------------|-----------|-------|---------|---------|
| プロジェクト一覧 | ProjectListTests | 9 | 5 | 0 | 4 |
| タスクボード | TaskBoardTests | 14 | 7 | 0 | 7 |
| エージェント管理 | AgentManagementTests | 15 | 6 | 0 | 9 |
| タスク詳細 | TaskDetailTests | 12 | 6 | 0 | 6 |
| 共通 | 複数クラス | 25 | 25 | 0 | 0 |
| 監査チーム | AuditTeamTests | 10 | 0 | 0 | 10 |
| 履歴 | HistoryTests | 10 | 0 | 0 | 10 |
| **合計** | | **95** | **49** | **0** | **46** |

### 改善点

2024-12-31の第2回更新で以下を改善:

1. **スタブから実装済みへ移行**: 全48個のスタブテストに具体的なアサーションを追加
2. **アクセシビリティ要素の検証**: `No Project Selected`, `No Selection` などの空状態メッセージを検証
3. **テストベースクラスの改善**: プロセス管理を改善し、テスト間の状態をクリーンに保持

### 残課題

- ⏳ 未実装のテストシナリオ（22件）はUIコンポーネント実装後に対応予定
- 一部テストは現時点でアクセス可能なUI要素（空状態メッセージ等）で検証しているため、実際のコンテンツ実装後に詳細な検証に更新が必要

## リアクティブ要件

**原則**: UIは状態変更に自動的に反応して更新されるべき（リアクティブ）

### テストでのリフレッシュ操作について

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

### 例外の扱い

どうしてもリアクティブが技術的に困難な場合：
1. **実装ファイル**に理由をコメントで明記
2. テストコードにも `// NOTE: リアクティブ例外 - 理由: ...` を記載

---

## シナリオ記載形式

各シナリオは以下の形式で記載:

```markdown
### TS-XX-YYY: シナリオ名

**目的**: テストの目的
**前提条件**: テスト実行前に必要な状態
**手順**:
1. 操作1
2. 操作2
3. ...

**期待結果**:
- 確認項目1
- 確認項目2

**PRD参照**: docs/ui/XX_yyyy.md
**実装状態**: ✅ 実装済み / 🔸 スタブ / ⏳ 未実装
**テストメソッド**: メソッド名（存在する場合）
```

## 命名規則

- `TS`: Test Scenario
- `XX`: 画面番号（01-05）
- `YYY`: シナリオ番号（001-999）

例: `TS-01-001` = プロジェクト一覧画面の1番目のシナリオ

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2024-12-31 | 初版作成（実装状況を「✅実装済み」と誤記） |
| 2024-12-31 | 実装状況を正確に修正（ほぼ全てスタブであることを明記） |
| 2024-12-31 | 全48スタブテストに具体的アサーションを実装、49テスト中48テストパス |
| 2024-12-31 | UIテスト基盤改善: SQLite journal cleanup, NotificationCenter連携, AppDelegate追加 |
| 2024-12-31 | macOS SwiftUI + XCUITest 制限事項を文書化（ターミナル実行不可） |
| 2025-01-01 | 要件再整理: サブタスク削除、Reviewカラム削除、監査チーム・履歴画面追加 |
| 2026-01-06 | リアクティブ要件追加: テストでのリフレッシュ操作は要件違反として扱う |
