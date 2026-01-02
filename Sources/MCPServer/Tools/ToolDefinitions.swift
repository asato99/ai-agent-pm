// Sources/MCPServer/Tools/ToolDefinitions.swift
// 参照: docs/prd/MCP_DESIGN.md - Tool定義
// 参照: docs/architecture/MCP_SERVER.md - MCPサーバー設計

import Foundation

/// MCP Tool定義を提供
enum ToolDefinitions {

    /// 全Tool一覧
    static func all() -> [[String: Any]] {
        [
            // Profile
            getMyProfile,

            // Session
            startSession,
            endSession,

            // Tasks
            listTasks,
            getTask,
            getMyTasks,
            createTask,
            updateTask,
            updateTaskStatus,
            assignTask,

            // Context
            saveContext,
            getTaskContext,

            // Handoff
            createHandoff,
            acceptHandoff,
            getPendingHandoffs
        ]
    }

    // MARK: - Profile Tools

    /// get_my_profile - 自分のエージェント情報を取得
    static let getMyProfile: [String: Any] = [
        "name": "get_my_profile",
        "description": "自分のエージェント情報を取得します。エージェントID、名前、役割、タイプ、ステータスが含まれます。",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ]

    // MARK: - Session Tools

    /// start_session - セッション開始
    static let startSession: [String: Any] = [
        "name": "start_session",
        "description": "作業セッションを開始します。セッション中はコンテキスト保存やハンドオフが可能になります。既にアクティブなセッションがある場合はエラーを返します。",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// end_session - セッション終了
    static let endSession: [String: Any] = [
        "name": "end_session",
        "description": "現在の作業セッションを終了します。セッションがない場合はエラーを返します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "status": [
                    "type": "string",
                    "description": "終了時のステータス: completed（完了）, abandoned（中断）",
                    "enum": ["completed", "abandoned"]
                ]
            ] as [String: Any],
            "required": [] as [String]
        ]
    ]

    // MARK: - Task Tools

    /// list_tasks - プロジェクト内の全タスクを取得
    static let listTasks: [String: Any] = [
        "name": "list_tasks",
        "description": "プロジェクト内の全タスク一覧を取得します。ステータスでフィルタ可能。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "status": [
                    "type": "string",
                    "description": "フィルタするステータス（任意）",
                    "enum": ["backlog", "todo", "in_progress", "in_review", "blocked", "done", "cancelled"]
                ]
            ] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// get_task - タスク詳細を取得
    static let getTask: [String: Any] = [
        "name": "get_task",
        "description": "指定したタスクの詳細情報を取得します。サブタスク、コンテキスト履歴も含まれます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "タスクID"
                ]
            ] as [String: Any],
            "required": ["task_id"]
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

    /// create_task - タスク作成
    static let createTask: [String: Any] = [
        "name": "create_task",
        "description": "新しいタスクを作成します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "title": [
                    "type": "string",
                    "description": "タスクのタイトル"
                ],
                "description": [
                    "type": "string",
                    "description": "タスクの詳細説明（任意）"
                ],
                "priority": [
                    "type": "string",
                    "description": "優先度（任意、デフォルト: medium）",
                    "enum": ["urgent", "high", "medium", "low"]
                ],
                "assignee_id": [
                    "type": "string",
                    "description": "担当者のエージェントID（任意）"
                ]
            ] as [String: Any],
            "required": ["title"]
        ]
    ]

    /// update_task - タスク更新
    static let updateTask: [String: Any] = [
        "name": "update_task",
        "description": "タスクの情報を更新します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "タスクID"
                ],
                "title": [
                    "type": "string",
                    "description": "新しいタイトル（任意）"
                ],
                "description": [
                    "type": "string",
                    "description": "新しい説明（任意）"
                ],
                "priority": [
                    "type": "string",
                    "description": "新しい優先度（任意）",
                    "enum": ["urgent", "high", "medium", "low"]
                ],
                "estimated_minutes": [
                    "type": "integer",
                    "description": "見積もり時間（分）（任意）"
                ],
                "actual_minutes": [
                    "type": "integer",
                    "description": "実績時間（分）（任意）"
                ]
            ] as [String: Any],
            "required": ["task_id"]
        ]
    ]

    /// update_task_status - タスクのステータスを更新
    static let updateTaskStatus: [String: Any] = [
        "name": "update_task_status",
        "description": "タスクのステータスを更新します。ステータス遷移ルールに従う必要があります。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "更新するタスクのID"
                ],
                "status": [
                    "type": "string",
                    "description": "新しいステータス",
                    "enum": ["backlog", "todo", "in_progress", "in_review", "blocked", "done", "cancelled"]
                ],
                "reason": [
                    "type": "string",
                    "description": "変更理由（任意）"
                ]
            ] as [String: Any],
            "required": ["task_id", "status"]
        ]
    ]

    /// assign_task - タスク割り当て
    static let assignTask: [String: Any] = [
        "name": "assign_task",
        "description": "タスクを指定のエージェントに割り当てます。assignee_idを省略すると割り当て解除になります。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "タスクID"
                ],
                "assignee_id": [
                    "type": "string",
                    "description": "担当者のエージェントID（省略で割り当て解除）"
                ]
            ] as [String: Any],
            "required": ["task_id"]
        ]
    ]

    // MARK: - Context Tools

    /// save_context - コンテキスト保存
    static let saveContext: [String: Any] = [
        "name": "save_context",
        "description": "タスクの作業コンテキストを保存します。進捗、発見事項、ブロッカー、次のステップを記録できます。アクティブなセッションが必要です。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "タスクID"
                ],
                "progress": [
                    "type": "string",
                    "description": "現在の進捗状況"
                ],
                "findings": [
                    "type": "string",
                    "description": "発見事項・学び"
                ],
                "blockers": [
                    "type": "string",
                    "description": "ブロッカー・課題"
                ],
                "next_steps": [
                    "type": "string",
                    "description": "次のステップ"
                ]
            ] as [String: Any],
            "required": ["task_id"]
        ]
    ]

    /// get_task_context - タスクコンテキスト取得
    static let getTaskContext: [String: Any] = [
        "name": "get_task_context",
        "description": "タスクの作業コンテキスト履歴を取得します。最新のコンテキストのみ、または全履歴を取得できます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "タスクID"
                ],
                "include_history": [
                    "type": "boolean",
                    "description": "全履歴を取得するか（デフォルト: false = 最新のみ）"
                ]
            ] as [String: Any],
            "required": ["task_id"]
        ]
    ]

    // MARK: - Handoff Tools

    /// create_handoff - ハンドオフ作成
    static let createHandoff: [String: Any] = [
        "name": "create_handoff",
        "description": "タスクを別のエージェントに引き継ぐためのハンドオフを作成します。サマリー、コンテキスト、推奨事項を記録できます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "task_id": [
                    "type": "string",
                    "description": "タスクID"
                ],
                "to_agent_id": [
                    "type": "string",
                    "description": "引き継ぎ先のエージェントID（省略で誰でも受け取れる）"
                ],
                "summary": [
                    "type": "string",
                    "description": "作業のサマリー"
                ],
                "context": [
                    "type": "string",
                    "description": "引き継ぎに必要なコンテキスト情報"
                ],
                "recommendations": [
                    "type": "string",
                    "description": "次のエージェントへの推奨事項"
                ]
            ] as [String: Any],
            "required": ["task_id", "summary"]
        ]
    ]

    /// accept_handoff - ハンドオフ承認
    static let acceptHandoff: [String: Any] = [
        "name": "accept_handoff",
        "description": "ハンドオフを受け入れて、タスクの作業を引き継ぎます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "handoff_id": [
                    "type": "string",
                    "description": "ハンドオフID"
                ]
            ] as [String: Any],
            "required": ["handoff_id"]
        ]
    ]

    /// get_pending_handoffs - 未処理ハンドオフ取得
    static let getPendingHandoffs: [String: Any] = [
        "name": "get_pending_handoffs",
        "description": "自分宛ての未処理ハンドオフを取得します。誰でも受け取れるハンドオフも含まれます。",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ]
}
