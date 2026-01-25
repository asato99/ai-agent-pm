# タスク実行ログ表示 TDD実装プラン

## 概要

`docs/design/TASK_EXECUTION_LOG_DISPLAY.md` の仕様を TDD で実装するための計画。

## テスト戦略

| レイヤー | ツール | 対象 |
|----------|--------|------|
| バックエンドAPI | XCTest | REST APIエンドポイント |
| フロントエンド | Vitest + React Testing Library | コンポーネント、フック |
| E2Eテスト | Playwright | ユーザーフロー、視覚的確認 |
| MSW | Mock Service Worker | API モック |

---

## Phase 1: バックエンドAPI（Swift）

### 1.1 ExecutionLogDTO作成

**ファイル**: `Sources/App/DTOs/ExecutionLogDTO.swift`

#### テスト

**ファイル**: `Tests/AppTests/DTOs/ExecutionLogDTOTests.swift`

```swift
final class ExecutionLogDTOTests: XCTestCase {
    func testExecutionLogDTOEncodesToJSON() throws {
        let dto = ExecutionLogDTO(
            id: "log-123",
            taskId: "task-1",
            agentId: "worker-1",
            agentName: "Worker 1",
            status: "completed",
            startedAt: Date(),
            completedAt: Date(),
            exitCode: 0,
            durationSeconds: 330.5,
            hasLogFile: true,
            errorMessage: nil,
            reportedProvider: "anthropic",
            reportedModel: "claude-3-5-sonnet"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["id"] as? String, "log-123")
        XCTAssertEqual(json["agentName"] as? String, "Worker 1")
        XCTAssertEqual(json["hasLogFile"] as? Bool, true)
    }

    func testExecutionLogDTOFromDomainModel() throws {
        let executionLog = ExecutionLog(
            id: "log-123",
            taskId: "task-1",
            agentId: "worker-1",
            status: .completed,
            startedAt: Date(),
            completedAt: Date(),
            exitCode: 0,
            durationSeconds: 330.5,
            logFilePath: "/path/to/log.txt",
            errorMessage: nil,
            reportedProvider: "anthropic",
            reportedModel: "claude-3-5-sonnet"
        )
        let agent = Agent(id: "worker-1", name: "Worker 1", role: "Developer")

        let dto = ExecutionLogDTO(from: executionLog, agentName: agent.name)

        XCTAssertEqual(dto.agentName, "Worker 1")
        XCTAssertTrue(dto.hasLogFile)
    }
}
```

#### 実装

**RED**: テスト実行 → 失敗（DTOが存在しない）

**GREEN**:

```swift
// Sources/App/DTOs/ExecutionLogDTO.swift
import Foundation

struct ExecutionLogDTO: Codable {
    let id: String
    let taskId: String
    let agentId: String
    let agentName: String
    let status: String
    let startedAt: Date
    let completedAt: Date?
    let exitCode: Int?
    let durationSeconds: Double?
    let hasLogFile: Bool
    let errorMessage: String?
    let reportedProvider: String?
    let reportedModel: String?

    init(from log: ExecutionLog, agentName: String) {
        self.id = log.id
        self.taskId = log.taskId
        self.agentId = log.agentId
        self.agentName = agentName
        self.status = log.status.rawValue
        self.startedAt = log.startedAt
        self.completedAt = log.completedAt
        self.exitCode = log.exitCode
        self.durationSeconds = log.durationSeconds
        self.hasLogFile = log.logFilePath != nil && !log.logFilePath!.isEmpty
        self.errorMessage = log.errorMessage
        self.reportedProvider = log.reportedProvider
        self.reportedModel = log.reportedModel
    }
}
```

---

### 1.2 ContextDTO作成

**ファイル**: `Sources/App/DTOs/ContextDTO.swift`

#### テスト

**ファイル**: `Tests/AppTests/DTOs/ContextDTOTests.swift`

```swift
final class ContextDTOTests: XCTestCase {
    func testContextDTOEncodesToJSON() throws {
        let dto = ContextDTO(
            id: "ctx-123",
            agentId: "worker-1",
            agentName: "Worker 1",
            sessionId: "session-456",
            progress: "APIエンドポイントの実装を開始",
            findings: "既存のauth middlewareを再利用可能",
            blockers: nil,
            nextSteps: "ユニットテストの追加",
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["id"] as? String, "ctx-123")
        XCTAssertEqual(json["progress"] as? String, "APIエンドポイントの実装を開始")
    }
}
```

#### 実装

```swift
// Sources/App/DTOs/ContextDTO.swift
import Foundation

struct ContextDTO: Codable {
    let id: String
    let agentId: String
    let agentName: String
    let sessionId: String
    let progress: String?
    let findings: String?
    let blockers: String?
    let nextSteps: String?
    let createdAt: Date
    let updatedAt: Date

    init(from context: Context, agentName: String) {
        self.id = context.id
        self.agentId = context.agentId
        self.agentName = agentName
        self.sessionId = context.sessionId
        self.progress = context.progress
        self.findings = context.findings
        self.blockers = context.blockers
        self.nextSteps = context.nextSteps
        self.createdAt = context.createdAt
        self.updatedAt = context.updatedAt
    }
}
```

---

### 1.3 GET /tasks/{taskId}/execution-logs エンドポイント

**ファイル**: `Sources/App/Controllers/TaskController.swift`

#### テスト

**ファイル**: `Tests/AppTests/Controllers/TaskControllerExecutionLogTests.swift`

```swift
final class TaskControllerExecutionLogTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = try await Application.testable()
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
    }

    func testGetExecutionLogsReturnsLogsForTask() async throws {
        // Setup: Create test data
        let task = try await createTestTask(id: "task-1")
        let agent = try await createTestAgent(id: "worker-1", name: "Worker 1")
        try await createTestExecutionLog(
            id: "log-1",
            taskId: "task-1",
            agentId: "worker-1",
            status: .completed
        )

        // Execute
        try await app.test(.GET, "/api/tasks/task-1/execution-logs") { response in
            XCTAssertEqual(response.status, .ok)

            let body = try response.content.decode(ExecutionLogsResponse.self)
            XCTAssertEqual(body.executionLogs.count, 1)
            XCTAssertEqual(body.executionLogs[0].id, "log-1")
            XCTAssertEqual(body.executionLogs[0].agentName, "Worker 1")
        }
    }

    func testGetExecutionLogsReturnsEmptyForTaskWithNoLogs() async throws {
        let task = try await createTestTask(id: "task-2")

        try await app.test(.GET, "/api/tasks/task-2/execution-logs") { response in
            XCTAssertEqual(response.status, .ok)

            let body = try response.content.decode(ExecutionLogsResponse.self)
            XCTAssertEqual(body.executionLogs.count, 0)
        }
    }

    func testGetExecutionLogsReturns404ForNonExistentTask() async throws {
        try await app.test(.GET, "/api/tasks/non-existent/execution-logs") { response in
            XCTAssertEqual(response.status, .notFound)
        }
    }

    func testGetExecutionLogsOrderedByStartedAtDescending() async throws {
        let task = try await createTestTask(id: "task-1")
        let agent = try await createTestAgent(id: "worker-1", name: "Worker 1")

        let oldDate = Date().addingTimeInterval(-3600)
        let newDate = Date()

        try await createTestExecutionLog(id: "log-old", taskId: "task-1", agentId: "worker-1", startedAt: oldDate)
        try await createTestExecutionLog(id: "log-new", taskId: "task-1", agentId: "worker-1", startedAt: newDate)

        try await app.test(.GET, "/api/tasks/task-1/execution-logs") { response in
            let body = try response.content.decode(ExecutionLogsResponse.self)
            XCTAssertEqual(body.executionLogs[0].id, "log-new")
            XCTAssertEqual(body.executionLogs[1].id, "log-old")
        }
    }
}
```

#### 実装

```swift
// Sources/App/Controllers/TaskController.swift

// 追加: 実行ログ一覧取得
func getExecutionLogs(req: Request) async throws -> ExecutionLogsResponse {
    guard let taskId = req.parameters.get("taskId") else {
        throw Abort(.badRequest, reason: "Task ID is required")
    }

    // タスク存在確認
    guard let _ = try await taskRepository.find(id: taskId) else {
        throw Abort(.notFound, reason: "Task not found")
    }

    // 実行ログ取得
    let logs = try await executionLogRepository.findByTaskId(taskId)

    // エージェント名をマップ
    let agentIds = Set(logs.map { $0.agentId })
    let agents = try await agentRepository.findByIds(Array(agentIds))
    let agentNameMap = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.name) })

    // DTOに変換
    let dtos = logs.map { log in
        ExecutionLogDTO(from: log, agentName: agentNameMap[log.agentId] ?? "Unknown")
    }

    return ExecutionLogsResponse(executionLogs: dtos)
}

// ルート登録
app.get("api", "tasks", ":taskId", "execution-logs", use: getExecutionLogs)
```

---

### 1.4 GET /execution-logs/{logId}/content エンドポイント

#### テスト

**ファイル**: `Tests/AppTests/Controllers/ExecutionLogContentTests.swift`

```swift
final class ExecutionLogContentTests: XCTestCase {
    func testGetLogContentReturnsFileContent() async throws {
        // Setup: ログファイルを一時的に作成
        let tempDir = FileManager.default.temporaryDirectory
        let logPath = tempDir.appendingPathComponent("test-log.txt")
        let logContent = "[2024-01-15 10:00:01] Starting task...\n[2024-01-15 10:05:30] Task completed."
        try logContent.write(to: logPath, atomically: true, encoding: .utf8)

        try await createTestExecutionLog(
            id: "log-1",
            taskId: "task-1",
            agentId: "worker-1",
            logFilePath: logPath.path
        )

        try await app.test(.GET, "/api/execution-logs/log-1/content") { response in
            XCTAssertEqual(response.status, .ok)

            let body = try response.content.decode(ExecutionLogContentResponse.self)
            XCTAssertEqual(body.content, logContent)
            XCTAssertEqual(body.filename, "test-log.txt")
            XCTAssertGreaterThan(body.fileSize, 0)
        }

        // Cleanup
        try FileManager.default.removeItem(at: logPath)
    }

    func testGetLogContentReturns404WhenNoLogFile() async throws {
        try await createTestExecutionLog(
            id: "log-no-file",
            taskId: "task-1",
            agentId: "worker-1",
            logFilePath: nil
        )

        try await app.test(.GET, "/api/execution-logs/log-no-file/content") { response in
            XCTAssertEqual(response.status, .notFound)
        }
    }

    func testGetLogContentReturns404WhenFileNotExists() async throws {
        try await createTestExecutionLog(
            id: "log-missing",
            taskId: "task-1",
            agentId: "worker-1",
            logFilePath: "/non/existent/path.log"
        )

        try await app.test(.GET, "/api/execution-logs/log-missing/content") { response in
            XCTAssertEqual(response.status, .notFound)
        }
    }
}
```

#### 実装

```swift
// Sources/App/Controllers/ExecutionLogController.swift

func getLogContent(req: Request) async throws -> ExecutionLogContentResponse {
    guard let logId = req.parameters.get("logId") else {
        throw Abort(.badRequest, reason: "Log ID is required")
    }

    guard let log = try await executionLogRepository.find(id: logId) else {
        throw Abort(.notFound, reason: "Execution log not found")
    }

    guard let logFilePath = log.logFilePath, !logFilePath.isEmpty else {
        throw Abort(.notFound, reason: "Log file path not set")
    }

    let fileURL = URL(fileURLWithPath: logFilePath)

    guard FileManager.default.fileExists(atPath: logFilePath) else {
        throw Abort(.notFound, reason: "Log file not found")
    }

    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let attributes = try FileManager.default.attributesOfItem(atPath: logFilePath)
    let fileSize = attributes[.size] as? Int ?? 0

    return ExecutionLogContentResponse(
        content: content,
        filename: fileURL.lastPathComponent,
        fileSize: fileSize
    )
}

// ルート登録
app.get("api", "execution-logs", ":logId", "content", use: getLogContent)
```

---

### 1.5 GET /tasks/{taskId}/contexts エンドポイント

#### テスト

**ファイル**: `Tests/AppTests/Controllers/TaskControllerContextTests.swift`

```swift
final class TaskControllerContextTests: XCTestCase {
    func testGetContextsReturnsContextsForTask() async throws {
        let task = try await createTestTask(id: "task-1")
        let agent = try await createTestAgent(id: "worker-1", name: "Worker 1")
        try await createTestContext(
            id: "ctx-1",
            taskId: "task-1",
            agentId: "worker-1",
            progress: "実装中"
        )

        try await app.test(.GET, "/api/tasks/task-1/contexts") { response in
            XCTAssertEqual(response.status, .ok)

            let body = try response.content.decode(ContextsResponse.self)
            XCTAssertEqual(body.contexts.count, 1)
            XCTAssertEqual(body.contexts[0].progress, "実装中")
            XCTAssertEqual(body.contexts[0].agentName, "Worker 1")
        }
    }

    func testGetContextsOrderedByUpdatedAtDescending() async throws {
        let task = try await createTestTask(id: "task-1")
        let agent = try await createTestAgent(id: "worker-1", name: "Worker 1")

        let oldDate = Date().addingTimeInterval(-3600)
        let newDate = Date()

        try await createTestContext(id: "ctx-old", taskId: "task-1", agentId: "worker-1", updatedAt: oldDate)
        try await createTestContext(id: "ctx-new", taskId: "task-1", agentId: "worker-1", updatedAt: newDate)

        try await app.test(.GET, "/api/tasks/task-1/contexts") { response in
            let body = try response.content.decode(ContextsResponse.self)
            XCTAssertEqual(body.contexts[0].id, "ctx-new")
            XCTAssertEqual(body.contexts[1].id, "ctx-old")
        }
    }
}
```

#### 実装

```swift
// Sources/App/Controllers/TaskController.swift

func getContexts(req: Request) async throws -> ContextsResponse {
    guard let taskId = req.parameters.get("taskId") else {
        throw Abort(.badRequest, reason: "Task ID is required")
    }

    guard let _ = try await taskRepository.find(id: taskId) else {
        throw Abort(.notFound, reason: "Task not found")
    }

    let contexts = try await contextRepository.findByTaskId(taskId)

    let agentIds = Set(contexts.map { $0.agentId })
    let agents = try await agentRepository.findByIds(Array(agentIds))
    let agentNameMap = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.name) })

    let dtos = contexts.map { context in
        ContextDTO(from: context, agentName: agentNameMap[context.agentId] ?? "Unknown")
    }

    return ContextsResponse(contexts: dtos)
}

// ルート登録
app.get("api", "tasks", ":taskId", "contexts", use: getContexts)
```

---

## Phase 2: フロントエンド型・フック

### 2.1 型定義

**ファイル**: `web-ui/src/types/executionLog.ts`

#### テスト（型チェック）

```bash
npm run typecheck
```

#### 実装

```typescript
// web-ui/src/types/executionLog.ts

export type ExecutionLogStatus = 'running' | 'completed' | 'failed'

export interface ExecutionLog {
  id: string
  taskId: string
  agentId: string
  agentName: string
  status: ExecutionLogStatus
  startedAt: string
  completedAt: string | null
  exitCode: number | null
  durationSeconds: number | null
  hasLogFile: boolean
  errorMessage: string | null
  reportedProvider: string | null
  reportedModel: string | null
}

export interface ExecutionLogContent {
  content: string
  filename: string
  fileSize: number
}

export interface TaskContext {
  id: string
  agentId: string
  agentName: string
  sessionId: string
  progress: string | null
  findings: string | null
  blockers: string | null
  nextSteps: string | null
  createdAt: string
  updatedAt: string
}

// 履歴タブ用の統合型
export type HistoryItemType = 'execution_log' | 'context'

export interface HistoryItem {
  type: HistoryItemType
  timestamp: string
  data: ExecutionLog | TaskContext
}
```

---

### 2.2 useExecutionLogs フック

**ファイル**: `web-ui/src/hooks/useExecutionLogs.ts`

#### テスト

**ファイル**: `web-ui/src/hooks/useExecutionLogs.test.ts`

```typescript
import { renderHook, waitFor } from '@testing-library/react'
import { useExecutionLogs } from './useExecutionLogs'
import { QueryClientWrapper } from '@/tests/utils'
import { server } from '@/tests/mocks/server'
import { http, HttpResponse } from 'msw'

describe('useExecutionLogs', () => {
  it('fetches execution logs for a task', async () => {
    server.use(
      http.get('/api/tasks/:taskId/execution-logs', () => {
        return HttpResponse.json({
          executionLogs: [
            {
              id: 'log-1',
              taskId: 'task-1',
              agentId: 'worker-1',
              agentName: 'Worker 1',
              status: 'completed',
              startedAt: '2024-01-15T10:00:00Z',
              completedAt: '2024-01-15T10:05:30Z',
              exitCode: 0,
              durationSeconds: 330.5,
              hasLogFile: true,
              errorMessage: null,
              reportedProvider: 'anthropic',
              reportedModel: 'claude-3-5-sonnet',
            },
          ],
        })
      })
    )

    const { result } = renderHook(() => useExecutionLogs('task-1'), {
      wrapper: QueryClientWrapper,
    })

    await waitFor(() => expect(result.current.isLoading).toBe(false))

    expect(result.current.executionLogs).toHaveLength(1)
    expect(result.current.executionLogs[0].agentName).toBe('Worker 1')
  })

  it('returns empty array when task has no logs', async () => {
    server.use(
      http.get('/api/tasks/:taskId/execution-logs', () => {
        return HttpResponse.json({ executionLogs: [] })
      })
    )

    const { result } = renderHook(() => useExecutionLogs('task-no-logs'), {
      wrapper: QueryClientWrapper,
    })

    await waitFor(() => expect(result.current.isLoading).toBe(false))

    expect(result.current.executionLogs).toHaveLength(0)
  })

  it('does not fetch when taskId is empty', () => {
    const { result } = renderHook(() => useExecutionLogs(''), {
      wrapper: QueryClientWrapper,
    })

    expect(result.current.isLoading).toBe(false)
    expect(result.current.executionLogs).toHaveLength(0)
  })
})
```

#### 実装

```typescript
// web-ui/src/hooks/useExecutionLogs.ts
import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { ExecutionLog } from '@/types/executionLog'

interface ExecutionLogsResponse {
  executionLogs: ExecutionLog[]
}

export function useExecutionLogs(taskId: string) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['executionLogs', taskId],
    queryFn: async () => {
      const result = await api.get<ExecutionLogsResponse>(
        `/tasks/${taskId}/execution-logs`
      )
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!taskId,
  })

  return {
    executionLogs: data?.executionLogs ?? [],
    isLoading,
    error,
  }
}
```

---

### 2.3 useTaskContexts フック

**ファイル**: `web-ui/src/hooks/useTaskContexts.ts`

#### テスト

**ファイル**: `web-ui/src/hooks/useTaskContexts.test.ts`

```typescript
import { renderHook, waitFor } from '@testing-library/react'
import { useTaskContexts } from './useTaskContexts'
import { QueryClientWrapper } from '@/tests/utils'
import { server } from '@/tests/mocks/server'
import { http, HttpResponse } from 'msw'

describe('useTaskContexts', () => {
  it('fetches contexts for a task', async () => {
    server.use(
      http.get('/api/tasks/:taskId/contexts', () => {
        return HttpResponse.json({
          contexts: [
            {
              id: 'ctx-1',
              agentId: 'worker-1',
              agentName: 'Worker 1',
              sessionId: 'session-456',
              progress: 'APIエンドポイント実装完了',
              findings: 'auth middleware再利用可能',
              blockers: null,
              nextSteps: 'ユニットテスト追加',
              createdAt: '2024-01-15T10:00:00Z',
              updatedAt: '2024-01-15T10:05:30Z',
            },
          ],
        })
      })
    )

    const { result } = renderHook(() => useTaskContexts('task-1'), {
      wrapper: QueryClientWrapper,
    })

    await waitFor(() => expect(result.current.isLoading).toBe(false))

    expect(result.current.contexts).toHaveLength(1)
    expect(result.current.contexts[0].progress).toBe('APIエンドポイント実装完了')
  })
})
```

#### 実装

```typescript
// web-ui/src/hooks/useTaskContexts.ts
import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { TaskContext } from '@/types/executionLog'

interface ContextsResponse {
  contexts: TaskContext[]
}

export function useTaskContexts(taskId: string) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['taskContexts', taskId],
    queryFn: async () => {
      const result = await api.get<ContextsResponse>(
        `/tasks/${taskId}/contexts`
      )
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!taskId,
  })

  return {
    contexts: data?.contexts ?? [],
    isLoading,
    error,
  }
}
```

---

### 2.4 useExecutionLogContent フック

**ファイル**: `web-ui/src/hooks/useExecutionLogContent.ts`

#### テスト

```typescript
describe('useExecutionLogContent', () => {
  it('fetches log content when enabled', async () => {
    server.use(
      http.get('/api/execution-logs/:logId/content', () => {
        return HttpResponse.json({
          content: '[2024-01-15 10:00:01] Starting...',
          filename: 'execution.log',
          fileSize: 1234,
        })
      })
    )

    const { result } = renderHook(
      () => useExecutionLogContent('log-1', true),
      { wrapper: QueryClientWrapper }
    )

    await waitFor(() => expect(result.current.isLoading).toBe(false))

    expect(result.current.content?.content).toContain('Starting')
    expect(result.current.content?.filename).toBe('execution.log')
  })

  it('does not fetch when disabled', () => {
    const { result } = renderHook(
      () => useExecutionLogContent('log-1', false),
      { wrapper: QueryClientWrapper }
    )

    expect(result.current.isLoading).toBe(false)
    expect(result.current.content).toBeUndefined()
  })
})
```

#### 実装

```typescript
// web-ui/src/hooks/useExecutionLogContent.ts
import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { ExecutionLogContent } from '@/types/executionLog'

export function useExecutionLogContent(logId: string, enabled: boolean) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['executionLogContent', logId],
    queryFn: async () => {
      const result = await api.get<ExecutionLogContent>(
        `/execution-logs/${logId}/content`
      )
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!logId && enabled,
  })

  return {
    content: data,
    isLoading,
    error,
  }
}
```

---

### 2.5 useTaskHistory フック（統合）

**ファイル**: `web-ui/src/hooks/useTaskHistory.ts`

#### テスト

```typescript
describe('useTaskHistory', () => {
  it('combines execution logs and contexts in chronological order', async () => {
    server.use(
      http.get('/api/tasks/:taskId/execution-logs', () => {
        return HttpResponse.json({
          executionLogs: [
            {
              id: 'log-1',
              startedAt: '2024-01-15T10:00:00Z',
              // ... other fields
            },
          ],
        })
      }),
      http.get('/api/tasks/:taskId/contexts', () => {
        return HttpResponse.json({
          contexts: [
            {
              id: 'ctx-1',
              updatedAt: '2024-01-15T10:05:00Z',
              // ... other fields
            },
          ],
        })
      })
    )

    const { result } = renderHook(() => useTaskHistory('task-1'), {
      wrapper: QueryClientWrapper,
    })

    await waitFor(() => expect(result.current.isLoading).toBe(false))

    expect(result.current.historyItems).toHaveLength(2)
    // Newer item first
    expect(result.current.historyItems[0].type).toBe('context')
    expect(result.current.historyItems[1].type).toBe('execution_log')
  })
})
```

#### 実装

```typescript
// web-ui/src/hooks/useTaskHistory.ts
import { useMemo } from 'react'
import { useExecutionLogs } from './useExecutionLogs'
import { useTaskContexts } from './useTaskContexts'
import type { HistoryItem, ExecutionLog, TaskContext } from '@/types/executionLog'

export function useTaskHistory(taskId: string) {
  const { executionLogs, isLoading: logsLoading } = useExecutionLogs(taskId)
  const { contexts, isLoading: contextsLoading } = useTaskContexts(taskId)

  const historyItems = useMemo(() => {
    const items: HistoryItem[] = []

    // Add execution logs
    executionLogs.forEach((log) => {
      items.push({
        type: 'execution_log',
        timestamp: log.startedAt,
        data: log,
      })
    })

    // Add contexts
    contexts.forEach((ctx) => {
      items.push({
        type: 'context',
        timestamp: ctx.updatedAt,
        data: ctx,
      })
    })

    // Sort by timestamp descending (newest first)
    items.sort((a, b) =>
      new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
    )

    return items
  }, [executionLogs, contexts])

  return {
    historyItems,
    isLoading: logsLoading || contextsLoading,
  }
}
```

---

## Phase 3: UIコンポーネント

### 3.1 TaskDetailPanel タブ構成

**ファイル**: `web-ui/src/components/task/TaskDetailPanel/TaskDetailPanel.tsx`

#### テスト

**ファイル**: `web-ui/src/components/task/TaskDetailPanel/TaskDetailPanel.test.tsx`

```typescript
describe('TaskDetailPanel - Tabs', () => {
  it('renders detail and history tabs', () => {
    render(<TaskDetailPanel task={mockTask} isOpen />)

    expect(screen.getByRole('tab', { name: '詳細' })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: '履歴' })).toBeInTheDocument()
  })

  it('shows detail tab content by default', () => {
    render(<TaskDetailPanel task={mockTask} isOpen />)

    expect(screen.getByTestId('task-detail-tab')).toBeVisible()
    expect(screen.queryByTestId('task-history-tab')).not.toBeVisible()
  })

  it('switches to history tab when clicked', async () => {
    render(<TaskDetailPanel task={mockTask} isOpen />)

    await userEvent.click(screen.getByRole('tab', { name: '履歴' }))

    expect(screen.queryByTestId('task-detail-tab')).not.toBeVisible()
    expect(screen.getByTestId('task-history-tab')).toBeVisible()
  })
})
```

#### 実装

```typescript
// TaskDetailPanel.tsx (抜粋)
import { useState } from 'react'
import { TaskDetailTab } from './TaskDetailTab'
import { TaskHistoryTab } from './TaskHistoryTab'

export function TaskDetailPanel({ task, isOpen, onClose, ...props }) {
  const [activeTab, setActiveTab] = useState<'detail' | 'history'>('detail')

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{task.title}</DialogTitle>
        </DialogHeader>

        {/* タブナビゲーション */}
        <div role="tablist" className="flex border-b">
          <button
            role="tab"
            aria-selected={activeTab === 'detail'}
            onClick={() => setActiveTab('detail')}
            className={/* styles */}
          >
            詳細
          </button>
          <button
            role="tab"
            aria-selected={activeTab === 'history'}
            onClick={() => setActiveTab('history')}
            className={/* styles */}
          >
            履歴
          </button>
        </div>

        {/* タブコンテンツ */}
        {activeTab === 'detail' ? (
          <TaskDetailTab
            data-testid="task-detail-tab"
            task={task}
            {...props}
          />
        ) : (
          <TaskHistoryTab
            data-testid="task-history-tab"
            taskId={task.id}
          />
        )}
      </DialogContent>
    </Dialog>
  )
}
```

---

### 3.2 TaskDetailTab コンポーネント

**ファイル**: `web-ui/src/components/task/TaskDetailPanel/TaskDetailTab.tsx`

既存の TaskDetailPanel の内容を分離。テストは既存のものを移動。

---

### 3.3 TaskHistoryTab コンポーネント

**ファイル**: `web-ui/src/components/task/TaskDetailPanel/TaskHistoryTab.tsx`

#### テスト

```typescript
describe('TaskHistoryTab', () => {
  it('renders loading state', () => {
    render(<TaskHistoryTab taskId="task-1" />)
    expect(screen.getByTestId('history-loading')).toBeInTheDocument()
  })

  it('renders empty state when no history', async () => {
    server.use(
      http.get('/api/tasks/:taskId/execution-logs', () =>
        HttpResponse.json({ executionLogs: [] })
      ),
      http.get('/api/tasks/:taskId/contexts', () =>
        HttpResponse.json({ contexts: [] })
      )
    )

    render(<TaskHistoryTab taskId="task-1" />)

    await waitFor(() => {
      expect(screen.getByText('履歴がありません')).toBeInTheDocument()
    })
  })

  it('renders execution log items', async () => {
    server.use(
      http.get('/api/tasks/:taskId/execution-logs', () =>
        HttpResponse.json({
          executionLogs: [{
            id: 'log-1',
            agentName: 'Worker 1',
            status: 'completed',
            startedAt: '2024-01-15T10:00:00Z',
            durationSeconds: 330,
            reportedModel: 'claude-3-5-sonnet',
          }],
        })
      ),
      http.get('/api/tasks/:taskId/contexts', () =>
        HttpResponse.json({ contexts: [] })
      )
    )

    render(<TaskHistoryTab taskId="task-1" />)

    await waitFor(() => {
      expect(screen.getByText('Worker 1')).toBeInTheDocument()
      expect(screen.getByText('実行完了')).toBeInTheDocument()
      expect(screen.getByText('claude-3-5-sonnet')).toBeInTheDocument()
    })
  })

  it('renders context items', async () => {
    server.use(
      http.get('/api/tasks/:taskId/execution-logs', () =>
        HttpResponse.json({ executionLogs: [] })
      ),
      http.get('/api/tasks/:taskId/contexts', () =>
        HttpResponse.json({
          contexts: [{
            id: 'ctx-1',
            agentName: 'Worker 1',
            progress: 'API実装完了',
            findings: 'middlewareを再利用',
            nextSteps: 'テスト追加',
            updatedAt: '2024-01-15T10:05:00Z',
          }],
        })
      )
    )

    render(<TaskHistoryTab taskId="task-1" />)

    await waitFor(() => {
      expect(screen.getByText('API実装完了')).toBeInTheDocument()
      expect(screen.getByText('middlewareを再利用')).toBeInTheDocument()
    })
  })
})
```

#### 実装

```typescript
// web-ui/src/components/task/TaskDetailPanel/TaskHistoryTab.tsx
import { useTaskHistory } from '@/hooks/useTaskHistory'
import { ExecutionLogItem } from '../HistoryItem/ExecutionLogItem'
import { ContextItem } from '../HistoryItem/ContextItem'

interface TaskHistoryTabProps {
  taskId: string
}

export function TaskHistoryTab({ taskId }: TaskHistoryTabProps) {
  const { historyItems, isLoading } = useTaskHistory(taskId)

  if (isLoading) {
    return <div data-testid="history-loading">読み込み中...</div>
  }

  if (historyItems.length === 0) {
    return <div className="text-gray-500 text-center py-8">履歴がありません</div>
  }

  return (
    <div className="space-y-4" data-testid="task-history-tab">
      {historyItems.map((item) => (
        item.type === 'execution_log' ? (
          <ExecutionLogItem key={item.data.id} log={item.data} />
        ) : (
          <ContextItem key={item.data.id} context={item.data} />
        )
      ))}
    </div>
  )
}
```

---

### 3.4 ExecutionLogItem コンポーネント

**ファイル**: `web-ui/src/components/task/HistoryItem/ExecutionLogItem.tsx`

#### テスト

```typescript
describe('ExecutionLogItem', () => {
  const mockLog: ExecutionLog = {
    id: 'log-1',
    taskId: 'task-1',
    agentId: 'worker-1',
    agentName: 'Worker 1',
    status: 'completed',
    startedAt: '2024-01-15T10:00:00Z',
    completedAt: '2024-01-15T10:05:30Z',
    exitCode: 0,
    durationSeconds: 330,
    hasLogFile: true,
    errorMessage: null,
    reportedProvider: 'anthropic',
    reportedModel: 'claude-3-5-sonnet',
  }

  it('renders completed status with checkmark', () => {
    render(<ExecutionLogItem log={mockLog} />)

    expect(screen.getByText('✅')).toBeInTheDocument()
    expect(screen.getByText('実行完了')).toBeInTheDocument()
  })

  it('renders failed status with error indicator', () => {
    const failedLog = { ...mockLog, status: 'failed' as const, errorMessage: 'API timeout' }
    render(<ExecutionLogItem log={failedLog} />)

    expect(screen.getByText('❌')).toBeInTheDocument()
    expect(screen.getByText('実行失敗')).toBeInTheDocument()
    expect(screen.getByText('API timeout')).toBeInTheDocument()
  })

  it('renders running status with spinner', () => {
    const runningLog = { ...mockLog, status: 'running' as const, completedAt: null }
    render(<ExecutionLogItem log={runningLog} />)

    expect(screen.getByText('🔄')).toBeInTheDocument()
    expect(screen.getByText('実行中')).toBeInTheDocument()
  })

  it('formats duration correctly', () => {
    render(<ExecutionLogItem log={mockLog} />)
    expect(screen.getByText('5分30秒')).toBeInTheDocument()
  })

  it('shows log viewer button when hasLogFile is true', () => {
    render(<ExecutionLogItem log={mockLog} />)
    expect(screen.getByRole('button', { name: 'ログ表示' })).toBeInTheDocument()
  })

  it('hides log viewer button when hasLogFile is false', () => {
    const noFileLog = { ...mockLog, hasLogFile: false }
    render(<ExecutionLogItem log={noFileLog} />)
    expect(screen.queryByRole('button', { name: 'ログ表示' })).not.toBeInTheDocument()
  })

  it('calls onViewLog when log button clicked', async () => {
    const onViewLog = vi.fn()
    render(<ExecutionLogItem log={mockLog} onViewLog={onViewLog} />)

    await userEvent.click(screen.getByRole('button', { name: 'ログ表示' }))
    expect(onViewLog).toHaveBeenCalledWith('log-1')
  })
})
```

#### 実装

```typescript
// web-ui/src/components/task/HistoryItem/ExecutionLogItem.tsx
import type { ExecutionLog } from '@/types/executionLog'
import { formatDuration, formatDateTime } from '@/utils/format'

interface ExecutionLogItemProps {
  log: ExecutionLog
  onViewLog?: (logId: string) => void
}

const statusConfig = {
  completed: { icon: '✅', label: '実行完了', color: 'text-green-600' },
  failed: { icon: '❌', label: '実行失敗', color: 'text-red-600' },
  running: { icon: '🔄', label: '実行中', color: 'text-blue-600' },
}

export function ExecutionLogItem({ log, onViewLog }: ExecutionLogItemProps) {
  const status = statusConfig[log.status]

  return (
    <div className="border rounded-lg p-4 bg-white">
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-2">
          <span className="text-lg">📋</span>
          <span className="text-sm text-gray-500">{formatDateTime(log.startedAt)}</span>
          <span className="font-medium">{log.agentName}</span>
        </div>
      </div>

      <div className="flex items-center gap-2 mb-2">
        <span>{status.icon}</span>
        <span className={status.color}>{status.label}</span>
        {log.durationSeconds && (
          <span className="text-gray-500">{formatDuration(log.durationSeconds)}</span>
        )}
      </div>

      {log.reportedModel && (
        <div className="text-sm text-gray-600 mb-2">{log.reportedModel}</div>
      )}

      {log.errorMessage && (
        <div className="text-sm text-red-600 bg-red-50 p-2 rounded">
          {log.errorMessage}
        </div>
      )}

      {log.hasLogFile && onViewLog && (
        <button
          onClick={() => onViewLog(log.id)}
          className="text-sm text-blue-600 hover:underline"
        >
          ログ表示
        </button>
      )}
    </div>
  )
}
```

---

### 3.5 ContextItem コンポーネント

**ファイル**: `web-ui/src/components/task/HistoryItem/ContextItem.tsx`

#### テスト

```typescript
describe('ContextItem', () => {
  const mockContext: TaskContext = {
    id: 'ctx-1',
    agentId: 'worker-1',
    agentName: 'Worker 1',
    sessionId: 'session-456',
    progress: 'APIエンドポイント実装完了',
    findings: 'auth middlewareを再利用可能',
    blockers: null,
    nextSteps: 'ユニットテスト追加',
    createdAt: '2024-01-15T10:00:00Z',
    updatedAt: '2024-01-15T10:05:30Z',
  }

  it('renders progress when present', () => {
    render(<ContextItem context={mockContext} />)
    expect(screen.getByText('進捗:')).toBeInTheDocument()
    expect(screen.getByText('APIエンドポイント実装完了')).toBeInTheDocument()
  })

  it('renders findings when present', () => {
    render(<ContextItem context={mockContext} />)
    expect(screen.getByText('発見:')).toBeInTheDocument()
    expect(screen.getByText('auth middlewareを再利用可能')).toBeInTheDocument()
  })

  it('renders blockers when present', () => {
    const withBlockers = { ...mockContext, blockers: 'API rate limit' }
    render(<ContextItem context={withBlockers} />)
    expect(screen.getByText('ブロッカー:')).toBeInTheDocument()
    expect(screen.getByText('API rate limit')).toBeInTheDocument()
  })

  it('renders nextSteps when present', () => {
    render(<ContextItem context={mockContext} />)
    expect(screen.getByText('次:')).toBeInTheDocument()
    expect(screen.getByText('ユニットテスト追加')).toBeInTheDocument()
  })

  it('does not render empty fields', () => {
    const minimal = { ...mockContext, findings: null, nextSteps: null }
    render(<ContextItem context={minimal} />)

    expect(screen.queryByText('発見:')).not.toBeInTheDocument()
    expect(screen.queryByText('次:')).not.toBeInTheDocument()
  })
})
```

#### 実装

```typescript
// web-ui/src/components/task/HistoryItem/ContextItem.tsx
import type { TaskContext } from '@/types/executionLog'
import { formatDateTime } from '@/utils/format'

interface ContextItemProps {
  context: TaskContext
}

export function ContextItem({ context }: ContextItemProps) {
  return (
    <div className="border rounded-lg p-4 bg-white">
      <div className="flex items-center gap-2 mb-2">
        <span className="text-lg">📝</span>
        <span className="text-sm text-gray-500">{formatDateTime(context.updatedAt)}</span>
        <span className="font-medium">{context.agentName}</span>
      </div>

      <div className="space-y-1 text-sm">
        {context.progress && (
          <div><span className="text-gray-500">進捗:</span> {context.progress}</div>
        )}
        {context.findings && (
          <div><span className="text-gray-500">発見:</span> {context.findings}</div>
        )}
        {context.blockers && (
          <div className="text-orange-600">
            <span className="text-gray-500">ブロッカー:</span> {context.blockers}
          </div>
        )}
        {context.nextSteps && (
          <div><span className="text-gray-500">次:</span> {context.nextSteps}</div>
        )}
      </div>
    </div>
  )
}
```

---

### 3.6 ExecutionLogViewer モーダル

**ファイル**: `web-ui/src/components/task/ExecutionLogViewer/ExecutionLogViewer.tsx`

#### テスト

```typescript
describe('ExecutionLogViewer', () => {
  it('renders log content when loaded', async () => {
    server.use(
      http.get('/api/execution-logs/:logId/content', () =>
        HttpResponse.json({
          content: '[2024-01-15 10:00:01] Starting task...',
          filename: 'execution.log',
          fileSize: 1234,
        })
      )
    )

    render(<ExecutionLogViewer logId="log-1" isOpen onClose={() => {}} />)

    await waitFor(() => {
      expect(screen.getByText(/Starting task/)).toBeInTheDocument()
    })
  })

  it('shows loading state', () => {
    render(<ExecutionLogViewer logId="log-1" isOpen onClose={() => {}} />)
    expect(screen.getByText('読み込み中...')).toBeInTheDocument()
  })

  it('shows error state when fetch fails', async () => {
    server.use(
      http.get('/api/execution-logs/:logId/content', () =>
        HttpResponse.json({ error: 'Not found' }, { status: 404 })
      )
    )

    render(<ExecutionLogViewer logId="log-1" isOpen onClose={() => {}} />)

    await waitFor(() => {
      expect(screen.getByText(/ログを読み込めませんでした/)).toBeInTheDocument()
    })
  })

  it('calls onClose when close button clicked', async () => {
    const onClose = vi.fn()
    render(<ExecutionLogViewer logId="log-1" isOpen onClose={onClose} />)

    await userEvent.click(screen.getByRole('button', { name: '閉じる' }))
    expect(onClose).toHaveBeenCalled()
  })
})
```

#### 実装

```typescript
// web-ui/src/components/task/ExecutionLogViewer/ExecutionLogViewer.tsx
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { useExecutionLogContent } from '@/hooks/useExecutionLogContent'

interface ExecutionLogViewerProps {
  logId: string
  isOpen: boolean
  onClose: () => void
  logInfo?: {
    agentName: string
    startedAt: string
    completedAt: string | null
    status: string
    reportedModel: string | null
    exitCode: number | null
  }
}

export function ExecutionLogViewer({ logId, isOpen, onClose, logInfo }: ExecutionLogViewerProps) {
  const { content, isLoading, error } = useExecutionLogContent(logId, isOpen)

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-w-4xl max-h-[80vh]">
        <DialogHeader>
          <DialogTitle>実行ログ</DialogTitle>
        </DialogHeader>

        {logInfo && (
          <div className="text-sm text-gray-600 space-y-1 mb-4">
            <div>📅 {logInfo.startedAt} - {logInfo.completedAt || '実行中'}</div>
            {logInfo.reportedModel && <div>🤖 {logInfo.reportedModel}</div>}
            <div>
              {logInfo.status === 'completed' ? '✅ 正常終了' :
               logInfo.status === 'failed' ? '❌ 失敗' : '🔄 実行中'}
              {logInfo.exitCode !== null && ` (exit: ${logInfo.exitCode})`}
            </div>
          </div>
        )}

        <div className="border rounded bg-gray-900 text-gray-100 p-4 overflow-auto max-h-[50vh] font-mono text-sm">
          {isLoading && <div className="text-gray-400">読み込み中...</div>}
          {error && <div className="text-red-400">ログを読み込めませんでした</div>}
          {content && <pre className="whitespace-pre-wrap">{content.content}</pre>}
        </div>

        <div className="flex justify-between items-center mt-4">
          {content && (
            <span className="text-sm text-gray-500">
              {content.filename} ({(content.fileSize / 1024).toFixed(1)} KB)
            </span>
          )}
          <button
            onClick={onClose}
            className="px-4 py-2 bg-gray-200 rounded hover:bg-gray-300"
          >
            閉じる
          </button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
```

---

## Phase 4: E2Eテスト

### 4.1 テストデータ追加

**ファイル**: `web-ui/e2e/scripts/seed-test-data.sql`

```sql
-- 実行ログテストデータ
INSERT INTO execution_logs (id, task_id, agent_id, status, started_at, completed_at, exit_code, duration_seconds, log_file_path, error_message, reported_provider, reported_model)
VALUES
  ('log-1', 'task-1', 'worker-1', 'completed', datetime('now', '-1 hour'), datetime('now', '-55 minutes'), 0, 300, '/tmp/test-log-1.txt', NULL, 'anthropic', 'claude-3-5-sonnet'),
  ('log-2', 'task-1', 'worker-1', 'failed', datetime('now', '-2 hours'), datetime('now', '-1 hour 50 minutes'), 1, 600, '/tmp/test-log-2.txt', 'API timeout', 'anthropic', 'claude-3-5-sonnet');

-- コンテキストテストデータ
INSERT INTO contexts (id, task_id, session_id, agent_id, progress, findings, blockers, next_steps, created_at, updated_at)
VALUES
  ('ctx-1', 'task-1', 'session-1', 'worker-1', 'APIエンドポイント実装完了', 'auth middleware再利用可能', NULL, 'ユニットテスト追加', datetime('now', '-50 minutes'), datetime('now', '-50 minutes'));
```

### 4.2 Page Object 拡張

**ファイル**: `web-ui/e2e/pages/task-board.page.ts`

```typescript
// 追加メソッド
async openTaskDetailPanel(taskId: string): Promise<void> {
  await this.page.locator(`[data-task-id="${taskId}"][data-testid="task-card"]`).click()
}

async switchToHistoryTab(): Promise<void> {
  await this.page.getByRole('tab', { name: '履歴' }).click()
}

async switchToDetailTab(): Promise<void> {
  await this.page.getByRole('tab', { name: '詳細' }).click()
}

async getHistoryItemCount(): Promise<number> {
  return await this.page.locator('[data-testid="history-item"]').count()
}

async clickViewLogButton(logIndex: number = 0): Promise<void> {
  await this.page.locator('[data-testid="history-item"]').nth(logIndex)
    .getByRole('button', { name: 'ログ表示' }).click()
}

async isLogViewerOpen(): Promise<boolean> {
  return await this.page.locator('[data-testid="log-viewer-modal"]').isVisible()
}

async closeLogViewer(): Promise<void> {
  await this.page.getByRole('button', { name: '閉じる' }).click()
}
```

### 4.3 E2E テストシナリオ

**ファイル**: `web-ui/e2e/tests/task-execution-log.spec.ts`

```typescript
import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { TaskBoardPage } from '../pages/task-board.page'

test.describe('Task Execution Log Display', () => {
  let taskBoard: TaskBoardPage

  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')

    taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('project-1')
  })

  test('displays detail and history tabs in task detail panel', async ({ page }) => {
    await taskBoard.openTaskDetailPanel('task-1')

    await expect(page.getByRole('tab', { name: '詳細' })).toBeVisible()
    await expect(page.getByRole('tab', { name: '履歴' })).toBeVisible()
  })

  test('shows detail tab content by default', async ({ page }) => {
    await taskBoard.openTaskDetailPanel('task-1')

    await expect(page.getByTestId('task-detail-tab')).toBeVisible()
  })

  test('switches to history tab and shows execution logs', async ({ page }) => {
    await taskBoard.openTaskDetailPanel('task-1')
    await taskBoard.switchToHistoryTab()

    await expect(page.getByTestId('task-history-tab')).toBeVisible()

    // 実行ログが表示される
    await expect(page.getByText('Worker 1')).toBeVisible()
    await expect(page.getByText('実行完了')).toBeVisible()
  })

  test('shows context items in history tab', async ({ page }) => {
    await taskBoard.openTaskDetailPanel('task-1')
    await taskBoard.switchToHistoryTab()

    await expect(page.getByText('進捗:')).toBeVisible()
    await expect(page.getByText('APIエンドポイント実装完了')).toBeVisible()
  })

  test('opens log viewer modal when clicking view log button', async ({ page }) => {
    await taskBoard.openTaskDetailPanel('task-1')
    await taskBoard.switchToHistoryTab()
    await taskBoard.clickViewLogButton(0)

    await expect(page.getByTestId('log-viewer-modal')).toBeVisible()
  })

  test('closes log viewer modal', async ({ page }) => {
    await taskBoard.openTaskDetailPanel('task-1')
    await taskBoard.switchToHistoryTab()
    await taskBoard.clickViewLogButton(0)

    await expect(page.getByTestId('log-viewer-modal')).toBeVisible()

    await taskBoard.closeLogViewer()

    await expect(page.getByTestId('log-viewer-modal')).not.toBeVisible()
  })

  test('displays error message for failed execution', async ({ page }) => {
    await taskBoard.openTaskDetailPanel('task-1')
    await taskBoard.switchToHistoryTab()

    await expect(page.getByText('実行失敗')).toBeVisible()
    await expect(page.getByText('API timeout')).toBeVisible()
  })

  test('shows empty state when task has no history', async ({ page }) => {
    // task-12 has no execution logs or contexts
    await taskBoard.openTaskDetailPanel('task-12')
    await taskBoard.switchToHistoryTab()

    await expect(page.getByText('履歴がありません')).toBeVisible()
  })
})
```

---

## 実装順序サマリー

| Phase | 内容 | テスト数(目安) | 工数 |
|-------|------|---------------|------|
| 1.1 | ExecutionLogDTO | 2 unit | 小 |
| 1.2 | ContextDTO | 1 unit | 小 |
| 1.3 | GET /execution-logs API | 4 unit | 中 |
| 1.4 | GET /log/content API | 3 unit | 中 |
| 1.5 | GET /contexts API | 2 unit | 小 |
| 2.1 | 型定義 | 型チェック | 小 |
| 2.2 | useExecutionLogs | 3 unit | 小 |
| 2.3 | useTaskContexts | 1 unit | 小 |
| 2.4 | useExecutionLogContent | 2 unit | 小 |
| 2.5 | useTaskHistory | 1 unit | 小 |
| 3.1 | TaskDetailPanel タブ | 3 unit | 中 |
| 3.2 | TaskDetailTab | 移行のみ | 小 |
| 3.3 | TaskHistoryTab | 4 unit | 中 |
| 3.4 | ExecutionLogItem | 7 unit | 中 |
| 3.5 | ContextItem | 5 unit | 小 |
| 3.6 | ExecutionLogViewer | 4 unit | 中 |
| 4 | E2E テスト | 8 e2e | 中 |

**合計**: バックエンドテスト約12件、フロントエンドユニットテスト約30件、E2Eテスト約8件

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-25 | 初版作成 |
