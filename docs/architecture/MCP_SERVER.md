# MCPサーバー アーキテクチャ設計

Claude Codeと連携するMCPサーバーの内部構成。

---

## 概要

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Claude Code                                     │
│                              │                                           │
│                         stdio (JSON-RPC)                                │
│                              │                                           │
└──────────────────────────────┼───────────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        mcp-server-pm                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                     Transport Layer                                │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  StdioTransport: stdin/stdout JSON-RPC 処理                  │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                               │                                          │
│  ┌───────────────────────────▼───────────────────────────────────────┐  │
│  │                     Protocol Layer                                 │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│  │  │   Tools     │  │  Resources  │  │   Prompts   │               │  │
│  │  │  Handler    │  │   Handler   │  │   Handler   │               │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘               │  │
│  └─────────┼────────────────┼────────────────┼───────────────────────┘  │
│            │                │                │                           │
│  ┌─────────▼────────────────▼────────────────▼───────────────────────┐  │
│  │                    Application Layer                               │  │
│  │                     (共有UseCases)                                 │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                               │                                          │
│  ┌───────────────────────────▼───────────────────────────────────────┐  │
│  │                    Infrastructure Layer                            │  │
│  │                  (共有Repository + Database)                       │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## ディレクトリ構造

```
Sources/MCPServer/
├── main.swift                      # エントリポイント
├── MCPServer.swift                 # サーバー本体
│
├── Transport/
│   ├── StdioTransport.swift        # stdin/stdout通信
│   └── Message.swift               # JSON-RPCメッセージ
│
├── Protocol/
│   ├── MCPProtocol.swift           # プロトコル定義
│   ├── ToolsHandler.swift          # Tools処理
│   ├── ResourcesHandler.swift      # Resources処理
│   └── PromptsHandler.swift        # Prompts処理
│
├── Tools/
│   ├── AgentTools.swift            # エージェント関連
│   ├── TaskTools.swift             # タスク関連
│   ├── ContextTools.swift          # コンテキスト関連
│   ├── HandoffTools.swift          # ハンドオフ関連
│   └── SessionTools.swift          # セッション関連
│
├── Resources/
│   ├── AgentResource.swift
│   ├── ProjectResource.swift
│   ├── TaskResource.swift
│   └── SessionResource.swift
│
├── Prompts/
│   ├── SessionStartPrompt.swift
│   ├── TaskStartPrompt.swift
│   ├── HandoffTemplatePrompt.swift
│   └── SessionEndPrompt.swift
│
└── Config/
    └── ServerConfig.swift          # 起動設定
```

---

## 起動フロー

### コマンドライン引数

```bash
mcp-server-pm \
  --db "/path/to/data.db" \
  --agent-id "agt_abc123"
```

### 起動処理

```swift
@main
struct MCPServerApp {
    static func main() async throws {
        // 1. 引数パース
        let config = try ServerConfig.parse()

        // 2. データベース接続
        let database = try DatabaseQueue(path: config.dbPath)

        // 3. DI設定
        let container = DependencyContainer(database: database)

        // 4. エージェント検証
        guard let agent = try await container.agentRepository
            .findById(AgentID(value: config.agentId)) else {
            throw MCPError.agentNotFound(config.agentId)
        }

        // 5. セッション開始
        let session = try await container.sessionUseCase.startSession(
            agentId: agent.id,
            toolType: .claudeCode
        )

        // 6. サーバー起動
        let server = MCPServer(
            config: config,
            container: container,
            currentAgent: agent,
            currentSession: session
        )

        // 7. シグナルハンドリング
        await server.setupSignalHandlers()

        // 8. メインループ
        try await server.run()
    }
}
```

---

## Transport Layer

### StdioTransport

```swift
actor StdioTransport {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput

    func readMessage() async throws -> JSONRPCRequest {
        // Content-Length ヘッダー読み取り
        guard let headerLine = readLine(),
              headerLine.hasPrefix("Content-Length: "),
              let length = Int(headerLine.dropFirst(16)) else {
            throw TransportError.invalidHeader
        }

        // 空行スキップ
        _ = readLine()

        // ボディ読み取り
        let data = input.readData(ofLength: length)
        return try JSONDecoder().decode(JSONRPCRequest.self, from: data)
    }

    func writeMessage(_ response: JSONRPCResponse) async throws {
        let data = try JSONEncoder().encode(response)
        let header = "Content-Length: \(data.count)\r\n\r\n"

        output.write(header.data(using: .utf8)!)
        output.write(data)
    }
}

struct JSONRPCRequest: Codable {
    let jsonrpc: String  // "2.0"
    let id: Int?
    let method: String
    let params: [String: AnyCodable]?
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String  // "2.0"
    let id: Int?
    let result: AnyCodable?
    let error: JSONRPCError?
}
```

---

## Protocol Layer

### MCPサーバー実装

```swift
actor MCPServer {
    private let transport: StdioTransport
    private let toolsHandler: ToolsHandler
    private let resourcesHandler: ResourcesHandler
    private let promptsHandler: PromptsHandler
    private let currentAgent: Agent
    private var currentSession: Session

    func run() async throws {
        while true {
            let request = try await transport.readMessage()
            let response = try await handleRequest(request)
            try await transport.writeMessage(response)
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        switch request.method {
        // 初期化
        case "initialize":
            return await handleInitialize(request)

        // Tools
        case "tools/list":
            return await toolsHandler.listTools()
        case "tools/call":
            return try await toolsHandler.callTool(request.params)

        // Resources
        case "resources/list":
            return await resourcesHandler.listResources()
        case "resources/read":
            return try await resourcesHandler.readResource(request.params)

        // Prompts
        case "prompts/list":
            return await promptsHandler.listPrompts()
        case "prompts/get":
            return try await promptsHandler.getPrompt(request.params)

        default:
            throw MCPError.unknownMethod(request.method)
        }
    }
}
```

---

## Tools実装

### ToolsHandler

```swift
actor ToolsHandler {
    private let agentTools: AgentTools
    private let taskTools: TaskTools
    private let contextTools: ContextTools
    private let handoffTools: HandoffTools
    private let sessionTools: SessionTools

    func listTools() async -> JSONRPCResponse {
        let tools: [ToolDefinition] = [
            // Agent Tools
            ToolDefinition(
                name: "get_my_profile",
                description: "自分のエージェント情報を取得",
                inputSchema: .empty
            ),
            ToolDefinition(
                name: "list_agents",
                description: "プロジェクトのエージェント一覧",
                inputSchema: .object(properties: [
                    "project_id": .string(description: "プロジェクトID")
                ])
            ),

            // Task Tools
            ToolDefinition(
                name: "get_my_tasks",
                description: "自分に割り当てられたタスク",
                inputSchema: .object(properties: [
                    "status": .string(description: "ステータスフィルタ", optional: true)
                ])
            ),
            ToolDefinition(
                name: "update_task_status",
                description: "タスクのステータスを更新",
                inputSchema: .object(properties: [
                    "task_id": .string(description: "タスクID"),
                    "status": .string(description: "新しいステータス"),
                    "reason": .string(description: "変更理由", optional: true)
                ])
            ),

            // Context Tools
            ToolDefinition(
                name: "add_context",
                description: "タスクにコンテキスト情報を追加",
                inputSchema: .object(properties: [
                    "task_id": .string(description: "タスクID"),
                    "content": .string(description: "内容"),
                    "type": .string(description: "種類: note, decision, assumption, blocker, reference, artifact")
                ])
            ),

            // Handoff Tools
            ToolDefinition(
                name: "create_handoff",
                description: "他エージェントへの引き継ぎを作成",
                inputSchema: .object(properties: [
                    "task_id": .string(description: "タスクID"),
                    "to_agent_id": .string(description: "引き継ぎ先エージェントID", optional: true),
                    "summary": .string(description: "作業サマリ"),
                    "next_steps": .array(description: "次のステップ"),
                    "warnings": .array(description: "注意点", optional: true)
                ])
            ),
            ToolDefinition(
                name: "get_pending_handoffs",
                description: "自分宛の未確認ハンドオフ一覧",
                inputSchema: .empty
            ),

            // Session Tools
            ToolDefinition(
                name: "end_session",
                description: "セッションを終了",
                inputSchema: .object(properties: [
                    "summary": .string(description: "セッションサマリ")
                ])
            )
        ]

        return JSONRPCResponse(result: ["tools": tools])
    }

    func callTool(_ params: [String: AnyCodable]?) async throws -> JSONRPCResponse {
        guard let name = params?["name"]?.value as? String,
              let arguments = params?["arguments"]?.value as? [String: Any] else {
            throw MCPError.invalidParams
        }

        let result: Any = switch name {
        case "get_my_profile":
            try await agentTools.getMyProfile()
        case "list_agents":
            try await agentTools.listAgents(projectId: arguments["project_id"] as? String)
        case "get_my_tasks":
            try await taskTools.getMyTasks(status: arguments["status"] as? String)
        case "update_task_status":
            try await taskTools.updateTaskStatus(
                taskId: arguments["task_id"] as! String,
                status: arguments["status"] as! String,
                reason: arguments["reason"] as? String
            )
        case "add_context":
            try await contextTools.addContext(
                taskId: arguments["task_id"] as! String,
                content: arguments["content"] as! String,
                type: arguments["type"] as! String
            )
        case "create_handoff":
            try await handoffTools.createHandoff(
                taskId: arguments["task_id"] as! String,
                toAgentId: arguments["to_agent_id"] as? String,
                summary: arguments["summary"] as! String,
                nextSteps: arguments["next_steps"] as! [String],
                warnings: arguments["warnings"] as? [String] ?? []
            )
        case "get_pending_handoffs":
            try await handoffTools.getPendingHandoffs()
        case "end_session":
            try await sessionTools.endSession(
                summary: arguments["summary"] as! String
            )
        default:
            throw MCPError.unknownTool(name)
        }

        return JSONRPCResponse(result: AnyCodable(result))
    }
}
```

---

## Resources実装

### ResourcesHandler

```swift
actor ResourcesHandler {
    func listResources() async -> JSONRPCResponse {
        let resources = [
            ResourceDefinition(uri: "agent://me", name: "My Agent", description: "自分のエージェント情報"),
            ResourceDefinition(uri: "session://current", name: "Current Session", description: "現在のセッション情報"),
            // 動的リソースはテンプレートとして定義
            ResourceTemplate(uriTemplate: "agent://{id}", name: "Agent by ID"),
            ResourceTemplate(uriTemplate: "project://{id}", name: "Project by ID"),
            ResourceTemplate(uriTemplate: "task://{id}", name: "Task by ID"),
            ResourceTemplate(uriTemplate: "context://{taskId}", name: "Task Context"),
            ResourceTemplate(uriTemplate: "handoff://{taskId}", name: "Task Handoff")
        ]

        return JSONRPCResponse(result: ["resources": resources])
    }

    func readResource(_ params: [String: AnyCodable]?) async throws -> JSONRPCResponse {
        guard let uri = params?["uri"]?.value as? String else {
            throw MCPError.invalidParams
        }

        let content = try await resolveResource(uri: uri)
        return JSONRPCResponse(result: ["contents": [content]])
    }

    private func resolveResource(uri: String) async throws -> ResourceContent {
        // URIパース
        let components = uri.split(separator: "://")
        guard components.count == 2 else {
            throw MCPError.invalidResourceUri(uri)
        }

        let scheme = String(components[0])
        let path = String(components[1])

        return switch scheme {
        case "agent":
            path == "me"
                ? try await agentResource.getMyAgent()
                : try await agentResource.getAgent(id: path)
        case "session":
            try await sessionResource.getCurrentSession()
        case "project":
            try await projectResource.getProject(id: path)
        case "task":
            try await taskResource.getTask(id: path)
        case "context":
            try await contextResource.getContext(taskId: path)
        case "handoff":
            try await handoffResource.getHandoff(taskId: path)
        default:
            throw MCPError.unknownResourceScheme(scheme)
        }
    }
}
```

---

## Prompts実装

### PromptsHandler

```swift
actor PromptsHandler {
    private let currentAgent: Agent
    private let container: DependencyContainer

    func listPrompts() async -> JSONRPCResponse {
        let prompts = [
            PromptDefinition(
                name: "session_start",
                description: "セッション開始時のガイダンス",
                arguments: []
            ),
            PromptDefinition(
                name: "task_start",
                description: "タスク開始時のガイダンス",
                arguments: [
                    PromptArgument(name: "task_id", description: "タスクID", required: true)
                ]
            ),
            PromptDefinition(
                name: "handoff_template",
                description: "ハンドオフ作成テンプレート",
                arguments: [
                    PromptArgument(name: "task_id", description: "タスクID", required: true)
                ]
            ),
            PromptDefinition(
                name: "session_end",
                description: "セッション終了時のサマリ作成ガイド",
                arguments: []
            )
        ]

        return JSONRPCResponse(result: ["prompts": prompts])
    }

    func getPrompt(_ params: [String: AnyCodable]?) async throws -> JSONRPCResponse {
        guard let name = params?["name"]?.value as? String else {
            throw MCPError.invalidParams
        }

        let arguments = params?["arguments"]?.value as? [String: String] ?? [:]

        let messages: [PromptMessage] = switch name {
        case "session_start":
            try await sessionStartPrompt()
        case "task_start":
            try await taskStartPrompt(taskId: arguments["task_id"]!)
        case "handoff_template":
            try await handoffTemplatePrompt(taskId: arguments["task_id"]!)
        case "session_end":
            try await sessionEndPrompt()
        default:
            throw MCPError.unknownPrompt(name)
        }

        return JSONRPCResponse(result: ["messages": messages])
    }

    private func sessionStartPrompt() async throws -> [PromptMessage] {
        let myTasks = try await container.taskUseCase.getTasksForAgent(agentId: currentAgent.id)
        let pendingHandoffs = try await container.handoffUseCase.getPendingHandoffs(forAgent: currentAgent.id)

        var content = """
        # セッション開始

        ## あなたの情報
        - 名前: \(currentAgent.name)
        - 役割: \(currentAgent.role)
        - 専門: \(currentAgent.capabilities.joined(separator: ", "))

        ## 担当タスク (\(myTasks.count)件)
        """

        for task in myTasks {
            content += "\n- [\(task.status.rawValue)] \(task.title)"
        }

        if !pendingHandoffs.isEmpty {
            content += "\n\n## 未確認のハンドオフ (\(pendingHandoffs.count)件)"
            for handoff in pendingHandoffs {
                content += "\n- \(handoff.summary)"
            }
        }

        return [PromptMessage(role: "user", content: content)]
    }
}
```

---

## セッション終了処理

### シグナルハンドリング

```swift
extension MCPServer {
    func setupSignalHandlers() async {
        // SIGTERM, SIGINT をハンドリング
        signal(SIGTERM) { _ in
            Task { await MCPServer.shared?.gracefulShutdown() }
        }
        signal(SIGINT) { _ in
            Task { await MCPServer.shared?.gracefulShutdown() }
        }
    }

    func gracefulShutdown() async {
        // セッション終了を記録
        try? await container.sessionUseCase.endSession(
            sessionId: currentSession.id,
            summary: "セッションが終了されました"
        )

        exit(0)
    }
}
```

---

## エラーハンドリング

```swift
enum MCPError: Error {
    case agentNotFound(String)
    case invalidParams
    case invalidHeader
    case unknownMethod(String)
    case unknownTool(String)
    case unknownPrompt(String)
    case unknownResourceScheme(String)
    case invalidResourceUri(String)
    case permissionDenied(String)
    case internalError(String)

    var code: Int {
        switch self {
        case .invalidParams: return -32602
        case .unknownMethod: return -32601
        case .internalError: return -32603
        default: return -32000
        }
    }

    var message: String {
        switch self {
        case .agentNotFound(let id): return "Agent not found: \(id)"
        case .invalidParams: return "Invalid params"
        case .unknownMethod(let m): return "Unknown method: \(m)"
        case .unknownTool(let t): return "Unknown tool: \(t)"
        case .permissionDenied(let r): return "Permission denied: \(r)"
        default: return String(describing: self)
        }
    }
}
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
