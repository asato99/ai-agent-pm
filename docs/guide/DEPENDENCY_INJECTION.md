# 依存性注入（DI）ガイドライン

本ドキュメントは依存性注入の原則と実装パターンを定義する。

---

## コンストラクタインジェクション必須

```swift
// ✅ Good: コンストラクタで依存を注入
final class CreateTaskUseCase: CreateTaskUseCaseProtocol {
    private let repository: TaskRepositoryProtocol

    init(repository: TaskRepositoryProtocol) {
        self.repository = repository
    }
}

// ❌ Bad: 内部で依存を生成
final class CreateTaskUseCase {
    private let repository = TaskRepository() // テスト不可能
}
```

---

## DIコンテナ

```swift
final class DependencyContainer {
    static let shared = DependencyContainer()

    // Protocol → 実装 のマッピング
    lazy var taskRepository: TaskRepositoryProtocol = {
        TaskRepository(dataStore: coreDataStore)
    }()

    lazy var createTaskUseCase: CreateTaskUseCaseProtocol = {
        CreateTaskUseCase(repository: taskRepository)
    }()
}
```

---

## テスト時の差し替え

```swift
// テストではMockを注入
func testCreateTask() {
    let mockRepository = MockTaskRepository()
    let useCase = CreateTaskUseCase(repository: mockRepository)

    // テスト実行
}
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | ARCHITECTURE.mdから分離して初版作成 |
