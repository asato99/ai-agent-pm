// Sources/MCPServer/Tools/ToolDefinitions.swift
// 参照: docs/prd/MCP_DESIGN.md - Tool定義
// 参照: docs/architecture/MCP_SERVER.md - MCPサーバー設計

import Foundation

/// MCP Tool定義を提供
enum ToolDefinitions {

    /// Phase 1で実装するTool一覧
    static func all() -> [[String: Any]] {
        [
            getMyProfile,
            listTasks,
            getMyTasks,
            updateTaskStatus
        ]
    }

    // MARK: - Tool Definitions

    /// get_my_profile - 自分のエージェント情報を取得
    static let getMyProfile: [String: Any] = [
        "name": "get_my_profile",
        "description": "自分のエージェント情報を取得します。エージェントID、名前、役割、タイプが含まれます。",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// list_tasks - プロジェクト内の全タスクを取得
    static let listTasks: [String: Any] = [
        "name": "list_tasks",
        "description": "プロジェクト内の全タスク一覧を取得します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "status": [
                    "type": "string",
                    "description": "フィルタするステータス（任意）: backlog, todo, in_progress, done",
                    "enum": ["backlog", "todo", "in_progress", "done"]
                ]
            ] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// get_my_tasks - 自分に割り当てられたタスクを取得
    static let getMyTasks: [String: Any] = [
        "name": "get_my_tasks",
        "description": "自分に割り当てられているタスク一覧を取得します。",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// update_task_status - タスクのステータスを更新
    static let updateTaskStatus: [String: Any] = [
        "name": "update_task_status",
        "description": "タスクのステータスを更新します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "更新するタスクのID"
                ],
                "status": [
                    "type": "string",
                    "description": "新しいステータス: backlog, todo, in_progress, done",
                    "enum": ["backlog", "todo", "in_progress", "done"]
                ]
            ] as [String: Any],
            "required": ["task_id", "status"]
        ]
    ]
}
