# 反省: UC004 タスク検出ロジックの問題

**日付**: 2026-01-08
**対象**: UC004統合テスト - `checkTaskStatusIsDone`関数

---

## 問題の概要

UC004統合テストで、タスクが画面上でDoneカラムに表示されているにもかかわらず、テストのアサートが失敗していた。

## 症状

- 画面上ではタスクがDoneカラムに正しく表示されている
- `report_completed`によるステータス更新は正常に動作
- しかしテストの`checkTaskStatusIsDone`関数がタスクを検出できない

## 原因分析

### 修正前のコード（問題あり）

```swift
// アプリ全体からタスクタイトルを含むボタンを検索
let taskButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", taskTitle)).firstMatch
if taskButton.exists {
    let taskFrame = taskButton.frame
    let doneFrame = doneColumn.frame
    // タスクがDoneカラム内にあるか確認（X座標で判定）
    if taskFrame.origin.x >= doneFrame.origin.x &&
       taskFrame.origin.x < doneFrame.origin.x + doneFrame.width {
        return true
    }
}
```

### 問題点

1. **座標の不正確さ**: スワイプでScrollViewをスクロールした後、要素の`frame`プロパティがScrollView内の論理位置を返し、実際の画面表示位置と一致しない
2. **タイトル検索の脆弱性**: ラベルにはタイトル以外の情報も含まれる場合がある（例: `"タイトル, assigned to エージェント名"`）
3. **検索範囲が広すぎ**: アプリ全体から検索するため、意図しない要素にマッチする可能性

## 解決策

### 修正後のコード

```swift
// タスクIDで直接検索（最も確実な方法）
let taskCardId = "TaskCard_\(taskId)"
let taskCard = app.descendants(matching: .any).matching(identifier: taskCardId).firstMatch
if taskCard.exists {
    // Doneカラムの位置を取得
    for col in doneColumns where col.frame.width > 100 {
        let doneFrame = col.frame
        let taskFrame = taskCard.frame
        // タスクがDoneカラム内にあるか確認（マージン付き）
        if taskFrame.origin.x >= doneFrame.origin.x - 50 &&
           taskFrame.origin.x < doneFrame.origin.x + doneFrame.width + 50 {
            return true
        }
    }
}
```

### 改善点

1. **accessibilityIdentifierで検索**: タスクIDを使った一意の識別子（`TaskCard_tsk_uc004_fe`）で検索
2. **座標比較にマージン追加**: ±50pxの許容範囲を設けてスクロール誤差を吸収
3. **フォールバック検索**: Doneカラム内のTaskCardを列挙して確認

## 教訓

### XCUITestでの要素検索

| 方法 | 信頼性 | 推奨度 |
|------|--------|--------|
| `accessibilityIdentifier`で検索 | 高 | 推奨 |
| `label`で部分一致検索 | 中 | 条件付き |
| 座標比較 | 低 | 避ける |

### ベストプラクティス

1. **IDベースの検索を優先**: 要素に一意のaccessibilityIdentifierを設定し、それで検索する
2. **座標に依存しない**: スクロール可能なビュー内の要素は座標が変動する
3. **マージンを設ける**: 座標比較が必要な場合は十分なマージンを持たせる
4. **スクリーンショットで確認**: 問題発生時はスクリーンショットで実際の画面状態を確認

## 関連ファイル

- `UITests/USECASE/UC004_MultiProjectSameAgentTests.swift`: 修正したテストファイル
- `Sources/App/Features/TaskBoard/TaskBoardView.swift`: TaskCardのaccessibility設定

## 反省

- ユーザーから「画面ではDoneになっている」と指摘されたにもかかわらず、実装側の問題を疑い続けた
- スクリーンショットを確認すれば問題の所在が明らかだったが、ログ解析に時間を費やした
- 「テストのアサートの問題」という指摘に対して、素直に検出ロジックを見直すべきだった
