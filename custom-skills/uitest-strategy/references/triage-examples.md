# トリアージ実例集

実際のテスト失敗から製品バグ/テスト問題を切り分けた具体例。

## 事例1: BPM Stepper操作失敗

### 症状
`testPartEditorBPMStepper_incrementWorks` が常に失敗。
コード内コメント `// Stepper cannot be operated via XCUITest with SwiftUI` により「既知の問題」として毎回スルーされていた。

### トリアージ過程

**Step 1: 分類** → B. 操作が期待通りに動かない

**Step 2b: 類似テスト比較**（決定的な切り分け手段）

同じUI部品（Stepper）を操作する別テスト `testPartEditorAdvancedSettings_keyCountStepperWorks` が**成功している**ことを発見。

差分分析:
| 項目 | BPMテスト（失敗） | Key Countテスト（成功） |
|-----|------------------|----------------------|
| DisclosureGroup展開 | なし | あり |
| スクロール | なし | `app.swipeUp()` あり |
| Stepper取得 | `steppers.firstMatch` | `steppers.element(boundBy: 1)` |

**仮説**: Stepperが画面外にあり、スクロールなしでは操作できない。

**Step 3: テスト側の問題と判断**
- [x] Key Count Stepperが成功 → Stepper操作は製品で正常動作
- [x] 同じUI部品の他テストが成功
- [x] スクロール不足というテスト固有の操作手順に問題あり

### 修正

```swift
// Before（失敗）
let bpmStepper = partEditor.steppers.firstMatch
bpmStepper.buttons["Increment"].tap()

// After（成功）
app.swipeUp()  // スクロール追加
Thread.sleep(forTimeInterval: 0.3)
let bpmStepper = partEditor.steppers.element(boundBy: 0)  // 明示的インデックス
bpmStepper.buttons["Increment"].tap()
```

### 教訓

1. **「既知の問題」は切り分け済みでない限り信用しない。** コメントに「XCUITestで操作不可」と書かれていても、同じ部品が成功しているテストがあれば疑う。
2. **類似テスト比較が最も有効な切り分け手段。** コード分析より実際に動いているテストとの差分分析の方が速く正確。
3. **スクロールは見落としやすい失敗原因。** Form/List内の要素は画面外にある可能性を常に考慮する。

---

## 事例2: Free Tier Exercise完了不能

### 症状
`testFreeTierAutoStopThenResumeToCompletion` でExerciseのpart completionに到達しない。
テストスコープを縮小（completion検証を除去）して対処していた。

### トリアージ過程

**Step 1: 分類** → C. タイムアウト（completionに到達しない）

**コード分析による切り分け**:

1. Free tierのauto-stop（30秒制限）後に `pausePractice()` が呼ばれる
2. `pausePractice()` は `scalePlaybackCoordinator.stopPlayback()` を呼ぶ → スケール状態が**完全クリア**
3. `resumePractice()` は `coordinator.isPaused` を確認するが、`stopPlayback()` 後は常にfalse
4. → スケールが毎回最初から再開される
5. 38秒のスケール（デフォルト設定）が30秒で毎回中断 → **永遠に完了しない**

**結論**: 製品バグ。`pausePractice()` が `stopPlayback()`（完全停止）を使うべきところで `pausePlayback()`（一時停止）を使うべきだった。

### 修正

- `ScalePlaybackCoordinator` に `pausePlayback()` / `resumePlayback()` を追加
- `ExerciseExecutionViewModel.pausePractice()` を `coordinator.pausePlayback()` に変更
- `resumePractice()` で `coordinator.isPaused` 分岐を追加

### 教訓

1. **テストスコープの縮小は製品バグを隠す。** completion検証を外したことで、Free Tierユーザーが完了できないバグが放置された。
2. **コード分析だけでも製品バグを発見できる。** テスト実行前の「なぜ完了しないか」の論理的分析が有効だった。
3. **非対称な操作ペア（pause/resume）はバグの温床。** `pausePractice()`と`resumePractice()`が異なるcoordinatorメソッドを使っていないか確認すべき。
