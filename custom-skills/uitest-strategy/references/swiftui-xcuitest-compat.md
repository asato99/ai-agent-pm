# SwiftUI XCUITest 互換性リファレンス

コンポーネント別の操作方法と注意点。すべて実際のテスト結果に基づく。

## Stepper

**結論: XCUITestで操作可能。** 「Stepper cannot be operated via XCUITest」は誤り。

### 操作方法

```swift
// 1. スクロールで表示領域に入れる（重要）
app.swipeUp()
Thread.sleep(forTimeInterval: 0.3)

// 2. インデックスで取得（コンテナ内の位置）
let stepper = partEditor.steppers.element(boundBy: 0) // BPM = 0番目
let stepper = partEditor.steppers.element(boundBy: 1) // Key Count = 1番目（Advanced展開後）

// 3. Increment/Decrementボタンで操作
stepper.buttons["Increment"].tap()
stepper.buttons["Decrement"].tap()

// 4. 値の検証
let value = stepper.value as? String  // "4" など
// またはラベルで確認
let bpm145 = app.staticTexts.element(matching: NSPredicate(format: "label CONTAINS %@", "145 BPM"))
```

### 失敗パターンと対策

| 失敗パターン | 原因 | 対策 |
|-------------|------|------|
| Stepperが見つからない | 画面外にある | `swipeUp()` でスクロール |
| Increment/Decrementが反応しない | 画面に一部しか表示されていない | スクロール後に0.3秒待機 |
| boundByインデックスがずれる | DisclosureGroup展開で順序変化 | 展開後のインデックスを確認 |

### 成功実績

- **BPM Stepper** (Form直下): `swipeUp()` → `boundBy: 0` → `Increment` → 140→145 確認 ✅
- **Key Count Stepper** (DisclosureGroup内): Advanced展開 → `swipeUp()` → `boundBy: 1` → `Decrement` → 5→4 確認 ✅

## Picker (menu style)

**操作可能。** SwiftUIの`.menu`スタイルPickerはbutton要素として表示される。

### 操作方法

```swift
// 1. 現在値のラベルでPicker（button）を特定
let picker = partEditor.buttons.matching(
    NSPredicate(format: "label CONTAINS %@", "5-Tone")
).firstMatch

// 2. タップしてメニュー展開
picker.tap()

// 3. メニューオプションを選択（hittable判定で重複回避）
let matches = app.buttons.matching(NSPredicate(format: "label == %@", "5-Tone Down"))
// 複数マッチする場合、isHittableなもの（メニューポップアップ）を選ぶ
for i in 0..<matches.count {
    let element = matches.element(boundBy: i)
    if element.isHittable {
        element.tap()
        break
    }
}

// 4. 変更確認
Thread.sleep(forTimeInterval: 0.5) // SwiftUI更新待ち
let updated = partEditor.buttons.matching(
    NSPredicate(format: "label CONTAINS %@", "Down")
).firstMatch
XCTAssertTrue(updated.waitForExistence(timeout: 3))
```

### 注意点

- メニュー選択後、背景に同じラベルのPickerボタンが残ることがある → `isHittable` で区別
- `Thread.sleep(forTimeInterval: 0.5)` でSwiftUIの状態更新を待つ

## DisclosureGroup

**操作可能。** ラベルマッチングでトグルボタンを取得。

```swift
let advancedToggle = partEditor.buttons.matching(
    NSPredicate(format: "label CONTAINS[c] %@", "Advanced")
).firstMatch
advancedToggle.tap()
Thread.sleep(forTimeInterval: 0.5) // アニメーション完了待ち

// 展開後にスクロールが必要な場合あり
app.swipeUp()
```

## 共通原則

1. **スクロール**: Form/List内の要素は画面外にある可能性が常にある → `swipeUp()` を先行
2. **待機**: SwiftUIのアニメーション・状態更新後に操作 → `Thread.sleep` または `waitForExistence`
3. **要素取得**: `accessibilityIdentifier` > `NSPredicate(label)` > `boundBy` の優先順位で取得
