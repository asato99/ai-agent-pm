# TDD（テスト駆動開発）ガイドライン

本ドキュメントはテスト駆動開発の原則とプラクティスを定義する。

---

## Red-Green-Refactorサイクル

```
1. Red    → 失敗するテストを書く
2. Green  → テストを通す最小限のコードを書く
3. Refactor → コードを改善する（テストは通ったまま）
```

---

## テストファースト必須ルール

```
⚠️ 新機能実装時のルール:

1. テストなしでプロダクションコードを書かない
2. 失敗するテストがない状態でプロダクションコードを書かない
3. テストを通すのに十分な以上のプロダクションコードを書かない
```

---

## テスト構造

```swift
// Given-When-Then パターン
func test_createTask_withValidTitle_returnsTask() async {
    // Given: 前提条件
    let useCase = CreateTaskUseCase(repository: MockTaskRepository())
    let input = CreateTaskInput(title: "Test Task")

    // When: テスト対象の実行
    let result = await useCase.execute(input: input)

    // Then: 期待結果の検証
    switch result {
    case .success(let task):
        XCTAssertEqual(task.title, "Test Task")
        XCTAssertFalse(task.isCompleted)
    case .failure:
        XCTFail("Expected success")
    }
}
```

---

## テストカテゴリ

| 種類 | 対象 | 実行速度 | 依存 |
|------|------|----------|------|
| **Unit Test** | Domain, UseCase | 高速 | なし（Mock使用） |
| **Integration Test** | Repository, DataStore | 中速 | 実DB（テスト用） |
| **UI Test** | View, ユーザーフロー | 低速 | 実アプリ |

---

## テストダブル使用指針

```swift
// Mock: 振る舞いを検証
final class MockTaskRepository: TaskRepositoryProtocol {
    var savedTasks: [Task] = []
    var saveCallCount = 0

    func save(_ task: Task) async throws {
        saveCallCount += 1
        savedTasks.append(task)
    }
}

// Stub: 固定値を返す
final class StubTaskRepository: TaskRepositoryProtocol {
    var taskToReturn: Task?

    func findById(_ id: TaskID) async throws -> Task? {
        return taskToReturn
    }
}
```

---

## テストメソッド命名

```swift
// パターン: test_{メソッド名}_{条件}_{期待結果}
func test_execute_withEmptyTitle_returnsValidationError()
func test_save_withValidTask_callsRepository()
func test_findById_whenNotExists_returnsNil()
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | ARCHITECTURE.mdから分離して初版作成 |
