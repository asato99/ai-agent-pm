# Clean Architecture ガイドライン

本ドキュメントはMacアプリ開発におけるクリーンアーキテクチャの原則を定義する。

---

## 依存関係ルール

```
外側 → 内側 への依存のみ許可
内側は外側を知らない
```

```
┌─────────────────────────────────────────────────┐
│  Frameworks & Drivers (外側)                    │
│  ┌─────────────────────────────────────────┐   │
│  │  Interface Adapters                      │   │
│  │  ┌─────────────────────────────────┐    │   │
│  │  │  Application Business Rules      │    │   │
│  │  │  ┌─────────────────────────┐    │    │   │
│  │  │  │  Enterprise Business    │    │    │   │
│  │  │  │  Rules (Entities)       │    │    │   │
│  │  │  └─────────────────────────┘    │    │   │
│  │  └─────────────────────────────────┘    │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

---

## レイヤー定義

| レイヤー | 責務 | 依存先 |
|---------|------|--------|
| **Domain** | ビジネスルール、Entity | なし |
| **UseCase** | アプリケーション固有ロジック | Domain |
| **Interface** | データ変換、Presenter、Repository実装 | UseCase, Domain |
| **Infrastructure** | フレームワーク、DB、UI | Interface, UseCase, Domain |

---

## 各レイヤーの構成要素

### Domain層（最内部）
```swift
// Entity: ビジネスオブジェクト
struct Task {
    let id: TaskID
    var title: String
    var isCompleted: Bool
}

// Value Object
struct TaskID: Equatable {
    let value: UUID
}

// Domain Service（複数Entityにまたがるロジック）
protocol TaskValidationService {
    func validate(_ task: Task) -> ValidationResult
}
```

### UseCase層
```swift
// UseCase Protocol
protocol CreateTaskUseCaseProtocol {
    func execute(input: CreateTaskInput) async -> Result<Task, TaskError>
}

// Input/Output DTO
struct CreateTaskInput {
    let title: String
}

// Repository Protocol（依存性逆転）
protocol TaskRepositoryProtocol {
    func save(_ task: Task) async throws
    func findById(_ id: TaskID) async throws -> Task?
}
```

### Interface層
```swift
// Presenter
protocol TaskPresenterProtocol {
    func present(_ task: Task) -> TaskViewModel
}

// Repository実装
final class TaskRepository: TaskRepositoryProtocol {
    private let dataStore: DataStoreProtocol

    func save(_ task: Task) async throws {
        // 実装
    }
}
```

### Infrastructure層
```swift
// SwiftUI View
struct TaskListView: View {
    @StateObject private var viewModel: TaskListViewModel
    // ...
}

// 外部フレームワーク統合
final class CoreDataStore: DataStoreProtocol {
    // CoreData実装
}
```

---

## ディレクトリ構造

```
Sources/
├── Domain/
│   ├── Entities/
│   │   └── Task.swift
│   ├── ValueObjects/
│   │   └── TaskID.swift
│   ├── Services/
│   │   └── TaskValidationService.swift
│   └── Errors/
│       └── DomainError.swift
│
├── UseCases/
│   ├── Task/
│   │   ├── CreateTaskUseCase.swift
│   │   ├── CreateTaskInput.swift
│   │   └── CreateTaskOutput.swift
│   └── Protocols/
│       └── TaskRepositoryProtocol.swift
│
├── Interface/
│   ├── Repositories/
│   │   └── TaskRepository.swift
│   ├── Presenters/
│   │   └── TaskPresenter.swift
│   └── ViewModels/
│       └── TaskViewModel.swift
│
└── Infrastructure/
    ├── UI/
    │   ├── Views/
    │   │   └── TaskListView.swift
    │   └── Components/
    │       └── TaskRowView.swift
    ├── DataStore/
    │   └── CoreDataStore.swift
    └── DI/
        └── DependencyContainer.swift

Tests/
├── DomainTests/
│   └── TaskTests.swift
├── UseCaseTests/
│   └── CreateTaskUseCaseTests.swift
├── InterfaceTests/
│   └── TaskRepositoryTests.swift
└── Mocks/
    └── MockTaskRepository.swift
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | ARCHITECTURE.mdから分離して初版作成 |
