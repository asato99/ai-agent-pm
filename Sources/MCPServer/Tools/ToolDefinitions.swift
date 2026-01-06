// Sources/MCPServer/Tools/ToolDefinitions.swift
// 参照: docs/prd/MCP_DESIGN.md - Tool定義（ステートレス設計）
// 参照: docs/architecture/MCP_SERVER.md - MCPサーバー設計

import Foundation

/// MCP Tool定義を提供
/// ステートレス設計: 必要なIDは全て引数として受け取る
enum ToolDefinitions {

    /// 全Tool一覧
    static func all() -> [[String: Any]] {
        [
            // Authentication (Phase 3-1)
            authenticate,

            // Agent
            getAgentProfile,
            getMyProfile,  // 後方互換性のため維持（非推奨）
            listAgents,

            // Project
            listProjects,
            getProject,

            // Tasks
            listTasks,
            getMyTasks,  // 後方互換性のため維持（非推奨）
            getPendingTasks,  // Phase 3-2: 作業中タスク取得
            getTask,
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

    // MARK: - Authentication Tools (Phase 3-1)

    /// authenticate - エージェント認証
    /// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md
    static let authenticate: [String: Any] = [
        "name": "authenticate",
        "description": "エージェントIDとパスキーで認証し、セッショントークンを取得します。Runnerがタスクを実行する前に呼び出します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID"
                ],
                "passkey": [
                    "type": "string",
                    "description": "エージェントのパスキー"
                ]
            ] as [String: Any],
            "required": ["agent_id", "passkey"]
        ]
    ]

    // MARK: - Agent Tools

    /// get_agent_profile - 指定エージェントの情報を取得
    static let getAgentProfile: [String: Any] = [
        "name": "get_agent_profile",
        "description": "指定したエージェントの情報を取得します。エージェントID、名前、役割、タイプが含まれます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID"
                ]
            ] as [String: Any],
            "required": ["agent_id"]
        ]
    ]

    /// get_my_profile - 後方互換性のため維持（非推奨）
    /// 新しいコードは get_agent_profile を使用すべき
    static let getMyProfile: [String: Any] = [
        "name": "get_my_profile",
        "description": "自分のエージェント情報を取得します。エージェントID、名前、役割、タイプが含まれます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID（キック時のプロンプトから取得）"
                ]
            ] as [String: Any],
            "required": ["agent_id"]
        ]
    ]

    /// list_agents - 全エージェント一覧を取得
    static let listAgents: [String: Any] = [
        "name": "list_agents",
        "description": "全エージェント一覧を取得します。",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ]

    // MARK: - Project Tools

    /// list_projects - 全プロジェクト一覧を取得
    static let listProjects: [String: Any] = [
        "name": "list_projects",
        "description": "全プロジェクト一覧を取得します。",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// get_project - プロジェクト詳細を取得
    static let getProject: [String: Any] = [
        "name": "get_project",
        "description": "指定したプロジェクトの詳細情報を取得します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "project_id": [
                    "type": "string",
                    "description": "プロジェクトID"
                ]
            ] as [String: Any],
            "required": ["project_id"]
        ]
    ]

    // MARK: - Task Tools

    /// list_tasks - 全タスク一覧を取得
    static let listTasks: [String: Any] = [
        "name": "list_tasks",
        "description": "タスク一覧を取得します。ステータスとアサイニーでフィルタ可能。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "status": [
                    "type": "string",
                    "description": "フィルタするステータス（任意）",
                    "enum": ["backlog", "todo", "in_progress", "blocked", "done", "cancelled"]
                ],
                "assignee_id": [
                    "type": "string",
                    "description": "フィルタするアサイニーのエージェントID（任意）"
                ]
            ] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// get_my_tasks - 後方互換性のため維持（非推奨）
    /// 新しいコードは list_tasks(assignee_id=...) を使用すべき
    static let getMyTasks: [String: Any] = [
        "name": "get_my_tasks",
        "description": "自分に割り当てられているタスク一覧を取得します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID（キック時のプロンプトから取得）"
                ]
            ] as [String: Any],
            "required": ["agent_id"]
        ]
    ]

    /// get_pending_tasks - Phase 3-2: 作業中タスク取得
    /// 外部Runnerが作業継続のため現在進行中のタスクを取得
    /// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md
    static let getPendingTasks: [String: Any] = [
        "name": "get_pending_tasks",
        "description": "指定エージェントの作業中（in_progress）タスク一覧を取得します。外部Runnerが作業継続のために使用します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID"
                ]
            ] as [String: Any],
            "required": ["agent_id"]
        ]
    ]

    /// get_task - タスク詳細を取得
    static let getTask: [String: Any] = [
        "name": "get_task",
        "description": "指定したタスクの詳細情報を取得します。最新のコンテキストも含まれます。",
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
                    "enum": ["backlog", "todo", "in_progress", "blocked", "done", "cancelled"]
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
        "description": "タスクの作業コンテキストを保存します。進捗、発見事項、ブロッカー、次のステップを記録できます。",
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
                ],
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID（任意、キック時のプロンプトから取得）"
                ],
                "session_id": [
                    "type": "string",
                    "description": "セッションID（任意）"
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
    /// ステートレス設計: from_agent_idは必須引数
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
                "from_agent_id": [
                    "type": "string",
                    "description": "引き継ぎ元のエージェントID（キック時のプロンプトから取得）"
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
            "required": ["task_id", "from_agent_id", "summary"]
        ]
    ]

    /// accept_handoff - ハンドオフ承認
    /// ステートレス設計: agent_idは必須引数
    static let acceptHandoff: [String: Any] = [
        "name": "accept_handoff",
        "description": "ハンドオフを受け入れて、タスクの作業を引き継ぎます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "handoff_id": [
                    "type": "string",
                    "description": "ハンドオフID"
                ],
                "agent_id": [
                    "type": "string",
                    "description": "受け入れるエージェントID（キック時のプロンプトから取得）"
                ]
            ] as [String: Any],
            "required": ["handoff_id", "agent_id"]
        ]
    ]

    /// get_pending_handoffs - 未処理ハンドオフ取得
    static let getPendingHandoffs: [String: Any] = [
        "name": "get_pending_handoffs",
        "description": "未処理のハンドオフ一覧を取得します。agent_idを指定すると、そのエージェント宛てと誰でも受け取れるハンドオフのみ返します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID（任意、キック時のプロンプトから取得）"
                ]
            ] as [String: Any],
            "required": [] as [String]
        ]
    ]
}
