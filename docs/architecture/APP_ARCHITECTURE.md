# Macアプリ アーキテクチャ設計

SwiftUIベースのMacアプリケーション内部構成。

---

## レイヤー構成

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AI Agent PM.app                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    Presentation Layer                              │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│  │  │   Views     │  │  ViewModels │  │   Router    │               │  │
│  │  │  (SwiftUI)  │  │ (@Observable)│  │ (Navigation)│               │  │
│  │  └─────────────┘  └──────┬──────┘  └─────────────┘               │  │
│  └──────────────────────────┼────────────────────────────────────────┘  │
│                              │                                           │
│  ┌──────────────────────────▼────────────────────────────────────────┐  │
│  │                    Application Layer                               │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│  │  │  UseCases   │  │ Presenters  │  │   Mappers   │               │  │
│  │  └──────┬──────┘  └─────────────┘  └─────────────┘               │  │
│  └─────────┼─────────────────────────────────────────────────────────┘  │
│            │                                                             │
│  ┌─────────▼─────────────────────────────────────────────────────────┐  │
│  │                      Domain Layer                                  │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│  │  │  Entities   │  │   Services  │  │ Repositories│               │  │
│  │  │             │  │  (Protocol) │  │  (Protocol) │               │  │
│  │  └─────────────┘  └─────────────┘  └──────┬──────┘               │  │
│  └───────────────────────────────────────────┼───────────────────────┘  │
│                                               │                          │
│  ┌───────────────────────────────────────────▼───────────────────────┐  │
│  │                   Infrastructure Layer                             │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│  │  │ Repositories│  │  Database   │  │   Config    │               │  │
│  │  │   (Impl)    │  │   (GRDB)    │  │  Services   │               │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘               │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## ディレクトリ構造

```
Sources/App/
├── App.swift                       # @main エントリポイント
├── DependencyContainer.swift       # DI設定
│
├── Presentation/
│   ├── Navigation/
│   │   ├── Router.swift            # ナビゲーション管理
│   │   └── NavigationPath.swift
│   │
│   ├── Views/
│   │   ├── ProjectList/
│   │   │   ├── ProjectListView.swift
│   │   │   ├── ProjectCardView.swift
│   │   │   └── ProjectListViewModel.swift
│   │   │
│   │   ├── TaskBoard/
│   │   │   ├── TaskBoardView.swift
│   │   │   ├── TaskColumnView.swift
│   │   │   ├── TaskCardView.swift
│   │   │   └── TaskBoardViewModel.swift
│   │   │
│   │   ├── TaskDetail/
│   │   │   ├── TaskDetailView.swift
│   │   │   ├── SubtaskListView.swift
│   │   │   ├── ContextListView.swift
│   │   │   ├── HistoryListView.swift
│   │   │   └── TaskDetailViewModel.swift
│   │   │
│   │   ├── AgentManagement/
│   │   │   ├── AgentListView.swift
│   │   │   ├── AgentDetailView.swift
│   │   │   ├── AgentCreateWizard/
│   │   │   │   ├── AgentCreateWizardView.swift
│   │   │   │   ├── Step1BasicInfoView.swift
│   │   │   │   ├── Step2CapabilitiesView.swift
│   │   │   │   └── Step3ConfigView.swift
│   │   │   └── AgentManagementViewModel.swift
│   │   │
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   ├── GeneralSettingsView.swift
│   │   │   ├── MCPSettingsView.swift
│   │   │   ├── AuditLogView.swift
│   │   │   └── SettingsViewModel.swift
│   │   │
│   │   └── Shared/
│   │       ├── LoadingView.swift
│   │       ├── ErrorView.swift
│   │       ├── EmptyStateView.swift
│   │       └── Components/
│   │           ├── StatusBadge.swift
│   │           ├── PriorityIndicator.swift
│   │           └── AgentAvatar.swift
│   │
│   └── Styles/
│       ├── Colors.swift
│       ├── Fonts.swift
│       └── Spacing.swift
│
└── Resources/
    ├── Assets.xcassets
    └── Localizable.strings
```

---

## ViewModel設計

### 基底ViewModel

```swift
@Observable
class BaseViewModel {
    var isLoading = false
    var error: AppError?

    func handleError(_ error: Error) {
        self.error = AppError.from(error)
    }
}
```

### ProjectListViewModel

```swift
@Observable
final class ProjectListViewModel: BaseViewModel {
    // State
    private(set) var projects: [Project] = []
    private(set) var projectSummaries: [ProjectID: ProjectSummary] = [:]
    var selectedProjectId: ProjectID?
    var sortOption: SortOption = .recentlyUpdated
    var filterOption: FilterOption = .all

    // Dependencies
    private let listProjectsUseCase: ListProjectsUseCaseProtocol
    private let getProjectSummaryUseCase: GetProjectSummaryUseCaseProtocol

    // Actions
    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }

        do {
            projects = try await listProjectsUseCase.execute(
                filter: filterOption,
                sort: sortOption
            )
            await loadSummaries()
        } catch {
            handleError(error)
        }
    }

    private func loadSummaries() async {
        for project in projects {
            if let summary = try? await getProjectSummaryUseCase.execute(projectId: project.id) {
                projectSummaries[project.id] = summary
            }
        }
    }
}
```

### TaskBoardViewModel

```swift
@Observable
final class TaskBoardViewModel: BaseViewModel {
    // State
    let project: Project
    private(set) var tasksByStatus: [TaskStatus: [Task]] = [:]
    private(set) var agents: [Agent] = []

    // Drag & Drop
    var draggedTask: Task?
    var dropTargetStatus: TaskStatus?

    // Actions
    func moveTask(_ task: Task, to status: TaskStatus) async {
        do {
            try await updateTaskStatusUseCase.execute(
                taskId: task.id,
                newStatus: status,
                reason: "ドラッグ&ドロップで移動"
            )
            await loadTasks()
        } catch {
            handleError(error)
        }
    }
}
```

---

## Navigation設計

### Router

```swift
@Observable
final class Router {
    var path = NavigationPath()
    var sheet: SheetDestination?
    var alert: AlertDestination?

    func navigate(to destination: Destination) {
        path.append(destination)
    }

    func present(sheet: SheetDestination) {
        self.sheet = sheet
    }

    func pop() {
        path.removeLast()
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}

enum Destination: Hashable {
    case projectList
    case taskBoard(Project)
    case taskDetail(Task)
    case agentDetail(Agent)
    case settings
}

enum SheetDestination: Identifiable {
    case createProject
    case createTask(Project)
    case createAgent(Project)
    case editTask(Task)

    var id: String {
        switch self {
        case .createProject: return "createProject"
        case .createTask(let p): return "createTask_\(p.id.value)"
        case .createAgent(let p): return "createAgent_\(p.id.value)"
        case .editTask(let t): return "editTask_\(t.id.value)"
        }
    }
}
```

### NavigationStack使用

```swift
struct ContentView: View {
    @State private var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            ProjectListView()
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .projectList:
                        ProjectListView()
                    case .taskBoard(let project):
                        TaskBoardView(project: project)
                    case .taskDetail(let task):
                        TaskDetailView(task: task)
                    case .agentDetail(let agent):
                        AgentDetailView(agent: agent)
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .environment(router)
        .sheet(item: $router.sheet) { sheet in
            // Sheet表示
        }
    }
}
```

---

## 依存性注入

### DependencyContainer

```swift
@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()

    // Infrastructure
    private lazy var database: DatabaseQueue = {
        let path = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("AI Agent PM")
            .appendingPathComponent("data.db")

        // ディレクトリ作成
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        return try! DatabaseQueue(path: path.path)
    }()

    // Repositories
    lazy var projectRepository: ProjectRepositoryProtocol = {
        ProjectRepository(database: database)
    }()

    lazy var taskRepository: TaskRepositoryProtocol = {
        TaskRepository(database: database)
    }()

    lazy var agentRepository: AgentRepositoryProtocol = {
        AgentRepository(database: database)
    }()

    lazy var eventRepository: EventRepositoryProtocol = {
        EventRepository(database: database)
    }()

    // UseCases
    lazy var listProjectsUseCase: ListProjectsUseCaseProtocol = {
        ListProjectsUseCase(repository: projectRepository)
    }()

    lazy var createTaskUseCase: CreateTaskUseCaseProtocol = {
        CreateTaskUseCase(
            taskRepository: taskRepository,
            eventRepository: eventRepository
        )
    }()

    // ViewModels
    func makeProjectListViewModel() -> ProjectListViewModel {
        ProjectListViewModel(
            listProjectsUseCase: listProjectsUseCase,
            getProjectSummaryUseCase: getProjectSummaryUseCase
        )
    }

    func makeTaskBoardViewModel(project: Project) -> TaskBoardViewModel {
        TaskBoardViewModel(
            project: project,
            listTasksUseCase: listTasksUseCase,
            updateTaskStatusUseCase: updateTaskStatusUseCase
        )
    }
}
```

---

## 状態管理パターン

### 単方向データフロー

```
┌────────────────────────────────────────────────────────┐
│                                                         │
│   View ──(action)──> ViewModel ──(call)──> UseCase     │
│     ▲                    │                    │         │
│     │                    │                    ▼         │
│     │                    │              Repository      │
│     │                    │                    │         │
│     └──(observe)─────────┴──(update state)────┘         │
│                                                         │
└────────────────────────────────────────────────────────┘
```

### リアクティブ更新

```swift
@Observable
final class TaskDetailViewModel {
    private(set) var task: Task
    private(set) var subtasks: [Subtask] = []
    private(set) var contexts: [Context] = []
    private(set) var history: [StateChangeEvent] = []

    // 変更監視
    private var cancellables = Set<AnyCancellable>()

    init(task: Task, ...) {
        self.task = task

        // DB変更を監視
        observeChanges()
    }

    private func observeChanges() {
        // GRDBのValueObservation使用
        taskRepository.observeTask(id: task.id)
            .sink { [weak self] updatedTask in
                self?.task = updatedTask
            }
            .store(in: &cancellables)
    }
}
```

---

## エラーハンドリング

### AppError

```swift
enum AppError: Error, LocalizedError {
    case notFound(entity: String, id: String)
    case validationFailed(message: String)
    case databaseError(underlying: Error)
    case networkError(underlying: Error)
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notFound(let entity, let id):
            return "\(entity)が見つかりません: \(id)"
        case .validationFailed(let message):
            return message
        case .databaseError:
            return "データベースエラーが発生しました"
        case .networkError:
            return "ネットワークエラーが発生しました"
        case .unknown:
            return "不明なエラーが発生しました"
        }
    }

    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .unknown(underlying: error)
    }
}
```

### ErrorView

```swift
struct ErrorView: View {
    let error: AppError
    let retryAction: (() async -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text(error.localizedDescription)
                .multilineTextAlignment(.center)

            if let retry = retryAction {
                Button("再試行") {
                    Task { await retry() }
                }
            }
        }
        .padding()
    }
}
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
