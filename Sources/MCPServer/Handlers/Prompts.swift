// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Prompts

extension MCPServer {

    // MARK: - Prompts List

    func handlePromptsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let prompts: [[String: Any]] = [
            [
                "name": "handoff",
                "description": "タスクのハンドオフを作成するための支援プロンプト。現在の進捗を整理し、次のエージェントへの引き継ぎ内容を生成します。",
                "arguments": [
                    [
                        "name": "task_id",
                        "description": "ハンドオフするタスクのID",
                        "required": true
                    ]
                ]
            ],
            [
                "name": "context-summary",
                "description": "タスクのコンテキストを要約するプロンプト。これまでの作業内容を整理して記録します。",
                "arguments": [
                    [
                        "name": "task_id",
                        "description": "コンテキストを要約するタスクのID",
                        "required": true
                    ]
                ]
            ],
            [
                "name": "task-breakdown",
                "description": "大きなタスクをサブタスクに分解するための支援プロンプト。",
                "arguments": [
                    [
                        "name": "task_id",
                        "description": "分解するタスクのID",
                        "required": true
                    ]
                ]
            ],
            [
                "name": "status-report",
                "description": "プロジェクトの状況報告を生成するプロンプト。",
                "arguments": [
                    [
                        "name": "project_id",
                        "description": "状況報告するプロジェクトのID",
                        "required": true
                    ]
                ]
            ]
        ]

        return JSONRPCResponse(id: request.id, result: ["prompts": prompts])
    }

    // MARK: - Prompts Get

    func handlePromptsGet(_ request: JSONRPCRequest) -> JSONRPCResponse {
        guard let params = request.params,
              let name = params["name"]?.stringValue else {
            return JSONRPCResponse(id: request.id, error: JSONRPCError.invalidParams)
        }

        let arguments = params["arguments"]?.dictionaryValue ?? [:]

        do {
            let messages = try getPrompt(name: name, arguments: arguments)
            return JSONRPCResponse(id: request.id, result: [
                "messages": messages
            ])
        } catch {
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32000, message: error.localizedDescription))
        }
    }

    func getPrompt(name: String, arguments: [String: Any]) throws -> [[String: Any]] {
        switch name {
        case "handoff":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try generateHandoffPrompt(taskId: taskId)
        case "context-summary":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try generateContextSummaryPrompt(taskId: taskId)
        case "task-breakdown":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try generateTaskBreakdownPrompt(taskId: taskId)
        case "status-report":
            guard let projectId = arguments["project_id"] as? String else {
                throw MCPError.missingArguments(["project_id"])
            }
            return try generateStatusReportPrompt(projectId: projectId)
        default:
            throw MCPError.unknownPrompt(name)
        }
    }

    func generateHandoffPrompt(taskId: String) throws -> [[String: Any]] {
        guard let task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        let contexts = try contextRepository.findByTask(task.id)

        var contextInfo = ""
        if let latestContext = contexts.last {
            contextInfo = """
            最新のコンテキスト:
            - 進捗: \(latestContext.progress ?? "なし")
            - 発見事項: \(latestContext.findings ?? "なし")
            - ブロッカー: \(latestContext.blockers ?? "なし")
            - 次のステップ: \(latestContext.nextSteps ?? "なし")
            """
        }

        let prompt = """
        以下のタスクについてハンドオフを作成してください。

        タスク情報:
        - ID: \(task.id.value)
        - タイトル: \(task.title)
        - 説明: \(task.description)
        - ステータス: \(task.status.rawValue)
        - 優先度: \(task.priority.rawValue)

        \(contextInfo)

        ハンドオフには以下を含めてください:
        1. これまでの作業のサマリー
        2. 現在の状態と残りの作業
        3. 次のエージェントへの推奨事項
        4. 注意すべき点やリスク
        """

        return [
            ["role": "user", "content": ["type": "text", "text": prompt]]
        ]
    }

    func generateContextSummaryPrompt(taskId: String) throws -> [[String: Any]] {
        guard let task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        let prompt = """
        以下のタスクの作業コンテキストを要約してください。

        タスク情報:
        - ID: \(task.id.value)
        - タイトル: \(task.title)
        - 説明: \(task.description)
        - ステータス: \(task.status.rawValue)

        以下の形式で要約を作成してください:
        1. 進捗状況 (progress): 現在の進捗を簡潔に
        2. 発見事項 (findings): 作業中に得た重要な発見や学び
        3. ブロッカー (blockers): 現在の障害や課題（あれば）
        4. 次のステップ (next_steps): 次に行うべきアクション
        """

        return [
            ["role": "user", "content": ["type": "text", "text": prompt]]
        ]
    }

    func generateTaskBreakdownPrompt(taskId: String) throws -> [[String: Any]] {
        guard let task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        let prompt = """
        以下のタスクを実行可能なステップに分解してください。

        タスク情報:
        - ID: \(task.id.value)
        - タイトル: \(task.title)
        - 説明: \(task.description)
        - 優先度: \(task.priority.rawValue)

        以下の観点でステップを提案してください:
        1. 各ステップは1つの具体的なアクションであること
        2. 完了の判断が明確であること
        3. 依存関係がある場合は順序を考慮すること

        提案するステップのリストを作成してください。
        """

        return [
            ["role": "user", "content": ["type": "text", "text": prompt]]
        ]
    }

    func generateStatusReportPrompt(projectId: String) throws -> [[String: Any]] {
        let pid = ProjectID(value: projectId)
        guard let project = try projectRepository.findById(pid) else {
            throw MCPError.projectNotFound(projectId)
        }

        let tasks = try taskRepository.findAll(projectId: pid)
        let agents = try agentRepository.findAll()

        let tasksByStatus = Dictionary(grouping: tasks) { $0.status }

        var statusSummary = "タスク状況:\n"
        for status in TaskStatus.allCases {
            let count = tasksByStatus[status]?.count ?? 0
            if count > 0 {
                statusSummary += "- \(status.rawValue): \(count)件\n"
            }
        }

        let prompt = """
        以下のプロジェクトの状況報告を作成してください。

        プロジェクト情報:
        - 名前: \(project.name)
        - 説明: \(project.description)
        - ステータス: \(project.status.rawValue)

        チーム:
        - エージェント数: \(agents.count)名
        - AIエージェント: \(agents.filter { $0.type == .ai }.count)名
        - 人間: \(agents.filter { $0.type == .human }.count)名

        \(statusSummary)

        状況報告には以下を含めてください:
        1. 全体の進捗サマリー
        2. 主な成果
        3. 課題とリスク
        4. 次のマイルストーン
        """

        return [
            ["role": "user", "content": ["type": "text", "text": prompt]]
        ]
    }


}
