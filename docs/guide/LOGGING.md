# ログ取得ベストプラクティス

macOS/iOS開発におけるログ取得の方式選択と実装ガイドライン。
特にXCUITest環境での確実なログ取得方法を重点的に解説する。

---

## 概要

### ログ方式の比較と選択基準

| 方式 | XCUITest環境 | 本番利用 | パフォーマンス | 用途 |
|------|-------------|---------|---------------|------|
| **ファイル出力** | ✅ 確実 | ❌ 非推奨 | △ | デバッグ専用 |
| **OSLog/Logger** | △ 要設定 | ✅ 推奨 | ✅ | 本番ログ |
| **NSLog** | ❌ キャプチャ困難 | △ | △ | レガシー |
| **print** | ❌ キャプチャ不可 | ❌ | ✅ | 開発時のみ |

### 選択フローチャート

```
XCUITestでのデバッグ？
  ├─ Yes → ファイルベースログを使用
  └─ No
       └─ 本番コード？
            ├─ Yes → OSLog/swift-log を使用
            └─ No → print で十分
```

---

## XCUITest環境向け: ファイルベースログ

XCUITest環境では**NSLog/printがキャプチャされない**ため、ファイル出力を使用する。

### 実装例

```swift
// DebugLog.swift
import Foundation

enum DebugLog {
    static let logFile = "/tmp/app_debug.log"

    static func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"

        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let handle = FileHandle(forWritingAtPath: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logFile, contents: data, attributes: nil)
            }
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(atPath: logFile)
    }
}
```

### 使用方法

```swift
// コード内でのログ出力
DebugLog.write("🔵 onDrag called for task: \(task.id.value)")
DebugLog.write("🟢 dropDestination called: status=\(status)")
DebugLog.write("🟠 Button clicked: \(buttonId)")
```

### ログ確認コマンド

```bash
# テスト前にクリア
rm -f /tmp/app_debug.log

# テスト実行
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:AIAgentPMUITests/TaskBoardTests/testDragAndDrop

# テスト実行後に確認
cat /tmp/app_debug.log

# リアルタイム監視
tail -f /tmp/app_debug.log
```

### 絵文字プレフィックス規約

視認性向上のため、カテゴリ別の絵文字を使用する：

| 絵文字 | カテゴリ | 例 |
|--------|---------|-----|
| 🔵 | ドラッグ開始 | `🔵 [DragDrop] draggable preview for task: ...` |
| 🟢 | ドロップ完了 | `🟢 [DragDrop] dropDestination called: ...` |
| 🟡 | 状態変化 | `🟡 [DragDrop] isTargeted changed to: true` |
| 🟠 | ユーザー操作 | `🟠 [Click] TaskCard clicked: ...` |
| 🔴 | エラー | `🔴 [Error] Failed to update: ...` |

---

## 本番向け: OSLog/Logger

### OSLog（標準ライブラリ）

```swift
import os.log

// カテゴリ別のログ定義
private let dragDropLog = OSLog(subsystem: "com.aiagentpm", category: "DragDrop")
private let taskLog = OSLog(subsystem: "com.aiagentpm", category: "Task")

// 使用例
os_log("onDrag called for task: %{public}@", log: dragDropLog, type: .debug, task.id.value)
os_log("Status changed: %{public}@ → %{public}@", log: taskLog, type: .info, oldStatus, newStatus)
```

### swift-log ライブラリ

```swift
import Logging

// ロガー初期化
var logger = Logger(label: "com.aiagentpm.dragdrop")
logger.logLevel = .debug

// 使用例
logger.debug("onDrag called", metadata: ["taskId": "\(task.id.value)"])
logger.info("Status changed", metadata: ["old": "\(old)", "new": "\(new)"])
logger.error("Update failed", metadata: ["error": "\(error)"])
```

### XCUITestでOSLogを取得する方法

```swift
// テストコード内でログを取得
import OSLog

func captureAppLogs() throws -> [OSLogEntryLog] {
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let position = store.position(timeIntervalSinceEnd: -60) // 過去60秒
    let entries = try store.getEntries(at: position)
        .compactMap { $0 as? OSLogEntryLog }
        .filter { $0.subsystem == "com.aiagentpm" }
    return entries
}
```

**注意**: アプリは別プロセスで動作するため、`scope: .currentProcessIdentifier` では取得できない場合がある。
その場合は `scope: .system` を使用するか、ファイルベースのログを推奨。

---

## ログレベルの使い分け

| レベル | 用途 | 本番で有効 | 例 |
|--------|------|-----------|-----|
| `trace` | 詳細なフロー追跡 | ❌ | ループ内の各イテレーション |
| `debug` | 開発時デバッグ情報 | 設定次第 | 関数呼び出し、状態変化 |
| `info` | 重要なイベント | ✅ | ユーザー操作、ステータス変更 |
| `warning` | 潜在的な問題 | ✅ | 非推奨API使用、リトライ発生 |
| `error` | エラー発生 | ✅ | 操作失敗、例外発生 |
| `critical` | 致命的エラー | ✅ | アプリクラッシュ、データ損失 |

```swift
// 適切なレベル選択の例
logger.trace("Processing item \(i) of \(total)")        // 詳細すぎる
logger.debug("Drag started for task: \(taskId)")        // 開発時有用
logger.info("Task status changed: \(old) → \(new)")     // 運用時も有用
logger.warning("Retrying API call: attempt \(n)")       // 注意が必要
logger.error("Failed to update status: \(error)")       // エラー
logger.critical("Database corruption detected")         // 致命的
```

---

## デバッグ時のチェックリスト

### 1. ログ出力自体が機能しているか確認

```swift
// 確実に呼ばれるコード（例: ボタンクリック）にもログを追加
Button("Test") {
    DebugLog.write("🟠 Test button clicked")  // これが出力されればログは機能している
    actualOperation()
}
```

### 2. ログ出力先を確認

```bash
# ファイルログ
cat /tmp/app_debug.log

# システムログ（OSLog使用時）
log stream --predicate 'subsystem == "com.aiagentpm"' --info

# システムログの過去分を検索
log show --predicate 'subsystem == "com.aiagentpm"' --last 5m
```

### 3. ログが出ない場合の原因切り分け

| 症状 | 原因 | 対処 |
|------|------|------|
| 全てのログが出ない | ログ出力先がキャプチャされていない | ファイルベースログに切り替え |
| 特定のログのみ出ない | そのコードが実行されていない | コールフロー確認、ブレークポイント設置 |
| ログレベルが低いものが出ない | ログレベルフィルタ | フィルタ設定を確認 |

---

## アンチパターンと正しいアプローチ

### ❌ アンチパターン

```
❌ 「XCUITestはSwiftUIのドラッグ&ドロップをサポートしていない」
   → 根拠なしに外部ツールの制限と結論

❌ 「NSLogを追加したがログが出ない、だから呼ばれていない」
   → NSLog出力がキャプチャされていない可能性を検討していない

❌ 「SwiftUIのバグだと思う」
   → 調査なしの推測
```

### ✅ 正しいアプローチ

```
✅ 「ファイルログで確認したところ:
    - クリックログは出力された（ログ出力は機能している）
    - onDropログは出力されなかった（コールバック未呼出を確認）
    - isTargetedログも出力されなかった（ドラッグ検出自体が機能していない）
    結論: XCUITestのドラッグ操作はSwiftUIのdropDestinationをトリガーしない」
   → 事実に基づいた問題特定と根拠ある結論
```

---

## 実例: XCUITestでのドラッグ&ドロップ調査

### 調査プロセス

1. **問題**: XCUITestでドラッグ操作後、タスクのステータスが変わらない

2. **仮説**:
   - A) 実装が間違っている
   - B) XCUITestのドラッグ操作がSwiftUIのコールバックをトリガーしない
   - C) ログ出力自体が機能していない

3. **検証**: ファイルベースログを追加
   ```swift
   // クリック操作（確実に呼ばれる）
   .onTapGesture {
       DebugLog.write("🟠 [Click] TaskCard clicked: \(task.id.value)")
   }

   // ドラッグ操作
   .draggable(...) {
       DebugLog.write("🔵 [DragDrop] draggable preview for task: \(task.id.value)")
   }

   .dropDestination(...) {
       DebugLog.write("🟢 [DragDrop] dropDestination called")
   }
   ```

4. **結果**:
   ```
   [2026-01-06T04:38:19Z] 🔵 [DragDrop] draggable preview for task: uitest_prerequisite_task
   [2026-01-06T04:38:27Z] 🟠 [Click] TaskCard clicked: uitest_prerequisite_task
   ```
   - クリックログ: ✅ 出力された（ログ機能は正常）
   - ドラッグプレビューログ: 出力された（初期化時のみ）
   - dropDestinationログ: ❌ 出力されない（コールバック未呼出）
   - isTargetedログ: ❌ 出力されない（ドラッグ検出なし）

5. **結論**: XCUITestの`press(forDuration:thenDragTo:)`はSwiftUIの`.dropDestination()`をトリガーしない
   - 根拠: ログ出力機能は正常動作している（クリックログで確認）
   - 根拠: ドラッグ関連のコールバックのみ呼ばれていない

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-06 | 初版作成: XCUITest環境でのログ取得問題を調査した結果をガイド化 |
