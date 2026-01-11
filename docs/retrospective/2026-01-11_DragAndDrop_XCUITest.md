# 調査・修正: タスクカードのドラッグ＆ドロップ機能

**日付**: 2026-01-11
**対象**: PRD02 TaskBoardTests - `testDragAndDropStatusChange`

---

## 問題の概要

タスクカードのドラッグ＆ドロップによるステータス変更機能が動作しなかった。

## 原因

**ButtonとonDragの競合**

`TaskCardButton`は`Button`でラップされており、外側に`onDrag`が適用されていた。`Button`がタップ/クリックイベントを消費するため、ドラッグジェスチャーが認識されなかった。

### 修正前のコード構造

```swift
TaskCardButton(task: task, agents: agents) { ... }  // Button内部
    .onDrag { ... }  // Buttonの外側にonDrag → ジェスチャー競合
```

## 修正内容

### 1. 新しい`DraggableTaskCard`コンポーネントを作成

- `Button`を使用せず、`onTapGesture`でクリックを処理
- `draggable`モディファイアを直接ビューに適用
- `Transferable`プロトコルを使用した`DraggableTaskID`を活用

```swift
struct DraggableTaskCard: View {
    var body: some View {
        TaskCardView(...)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { onTap() }
            .draggable(DraggableTaskID(taskId: task.id)) { ... }
    }
}
```

### 2. ドロップ処理を`dropDestination`に変更

- `onDrop`（NSItemProvider使用）から`dropDestination`（Transferable使用）に変更
- `draggable`と`dropDestination`は同じ`Transferable`型を使用

```swift
.dropDestination(for: DraggableTaskID.self) { droppedItems, _ in
    guard let droppedItem = droppedItems.first else { return false }
    onTaskDropped(droppedItem.taskId, status)
    return true
}
```

## 変更ファイル

- `Sources/App/Features/TaskBoard/TaskBoardView.swift`
  - `DraggableTaskCard`コンポーネント追加（591-626行）
  - `TaskColumnView`で`DraggableTaskCard`を使用（457-465行）
  - `dropDestination`に変更（479-491行）

## 検証結果

### 手動テスト
✅ 動作確認済み

### UIテスト
✅ `testDragAndDropStatusChange` パス（22.863秒）

### ログ出力（実際の結果）
```
🟡 [dropDestination] isTargeted changed to: true for column: backlog
🔵 [draggable] preview shown for task: uitest_prerequisite_task
🟡 [dropDestination] isTargeted changed to: false for column: backlog
🟡 [dropDestination] isTargeted changed to: true for column: todo
🟢 [dropDestination] drop called for column: todo, items count: 1
🟢 [dropDestination] Dropped taskId: uitest_prerequisite_task
```

## 教訓

| 問題 | 原因 | 解決策 |
|------|------|--------|
| ButtonとonDragの競合 | Buttonがジェスチャーを消費 | onTapGesture + draggableを使用 |
| onDragとdropDestinationの不一致 | 異なるAPI使用 | 両方Transferableを使用 |
| XCUITestでドラッグ不可（旧実装） | Button+onDragの問題 | 上記修正で解決 |
| TaskDetailViewが更新されない | @Stateのみ使用、TaskStore未監視 | TaskStoreObserverでCombineサブスクライブ |

---

## 追加修正: TaskDetailViewリアクティブ更新（2026-01-11 12:15）

### 問題

ドラッグ&ドロップでステータス変更後、TaskDetailViewが自動更新されなかった。
カードを再クリックすると更新されるが、リアクティブ要件に違反。

### 原因

`TaskDetailView`が`@State private var task: Task?`のみを使用し、`TaskStore`の変更を監視していなかった。

### 修正内容

1. **TaskStoreObserverクラスを追加**
   - Combineの`$tasks.sink`でTaskStoreのtasks配列を監視
   - タスク変更を`@Published var tasks`で公開

```swift
@MainActor
private final class TaskStoreObserver: ObservableObject {
    @Published var tasks: [Task] = []
    private var cancellable: AnyCancellable?

    init(taskStore: TaskStore?) {
        if let store = taskStore {
            cancellable = store.$tasks.sink { [weak self] newTasks in
                self?.tasks = newTasks
            }
            tasks = store.tasks
        }
    }
}
```

2. **TaskDetailViewでonChangeハンドラを追加**

```swift
.onChange(of: storeObserver.tasks) { _, newTasks in
    if let updatedTask = newTasks.first(where: { $0.id == taskId }) {
        task = updatedTask
    }
}
```

### 検証結果

✅ UIテスト `testDragAndDropStatusChange` パス（リアクティブ検証版）

```
🔵 [TEST] Status before drag: Backlog
🔵 [TEST] Status after drag (without re-clicking): To Do
```
