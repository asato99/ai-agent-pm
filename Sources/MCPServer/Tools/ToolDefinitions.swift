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
            // Phase 4: Runner API
            healthCheck,
            listManagedAgents,
            listActiveProjectsWithAgents,
            shouldStart,

            // Phase 4: Agent API
            authenticate,  // instruction追加
            getMyTask,
            reportCompleted,

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
            getPendingTasks,  // Phase 3-2: 作業中タスク取得（Phase 4で非推奨）
            getTask,
            updateTaskStatus,
            assignTask,

            // Context
            saveContext,
            getTaskContext,

            // Handoff
            createHandoff,
            acceptHandoff,
            getPendingHandoffs,

            // Execution Log (Phase 3-3, Phase 4で非推奨)
            reportExecutionStart,
            reportExecutionComplete,

            // Phase 4: Coordinator用（認証不要）
            registerExecutionLogFile
        ]
    }

    // MARK: - Phase 4: Runner API

    /// health_check - サーバー起動確認
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Runnerが最初に呼び出す。サーバーが応答可能かを確認。
    static let healthCheck: [String: Any] = [
        "name": "health_check",
        "description": "MCPサーバーの起動状態を確認します。Runnerがポーリングの最初に呼び出します。",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// list_managed_agents - 管理対象エージェント一覧を取得
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Runnerがポーリング対象のエージェントIDを取得。詳細は隠蔽。
    static let listManagedAgents: [String: Any] = [
        "name": "list_managed_agents",
        "description": "Runnerの管理対象となるAIエージェントのID一覧を取得します。エージェントの詳細は隠蔽されます。",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// list_active_projects_with_agents - アクティブなプロジェクトと割り当てエージェント一覧を取得
    /// 参照: docs/requirements/PROJECTS.md - MCP API
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    static let listActiveProjectsWithAgents: [String: Any] = [
        "name": "list_active_projects_with_agents",
        "description": "アクティブなプロジェクト一覧と、各プロジェクトに割り当てられたエージェントを取得します。Runnerがポーリング対象を決定するために使用します。",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// should_start - エージェントを起動すべきかどうかを返す
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Runnerはタスクの詳細を知らない。boolのみ返す。
    /// Phase 4: project_idを追加（(agent_id, project_id)単位で起動判断）
    static let shouldStart: [String: Any] = [
        "name": "should_start",
        "description": "エージェントを起動すべきかどうかを判定します。Runnerが使用します。タスク詳細は返さず、起動判断のみを提供します。Phase 4では(agent_id, project_id)の組み合わせで判定します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID"
                ],
                "project_id": [
                    "type": "string",
                    "description": "プロジェクトID（Phase 4: 必須）"
                ]
            ] as [String: Any],
            "required": ["agent_id", "project_id"]
        ]
    ]

    // MARK: - Phase 4: Agent API

    /// authenticate - エージェント認証
    /// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md, PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Phase 4: project_id 必須、instruction フィールドを追加
    static let authenticate: [String: Any] = [
        "name": "authenticate",
        "description": "エージェントIDとパスキーとプロジェクトIDで認証し、セッショントークンとinstructionを取得します。Phase 4ではセッションは(agent_id, project_id)の組み合わせに紐づきます。Agentが起動後に最初に呼び出します。instructionに従って次のアクション（get_my_task）を実行してください。",
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
                ],
                "project_id": [
                    "type": "string",
                    "description": "プロジェクトID（Phase 4: 必須）"
                ]
            ] as [String: Any],
            "required": ["agent_id", "passkey", "project_id"]
        ]
    ]

    /// get_my_task - 現在のタスクを取得
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    static let getMyTask: [String: Any] = [
        "name": "get_my_task",
        "description": "認証済みエージェントの現在のタスク詳細を取得します。タスクがあればcontextやhandoff情報も含まれます。instructionに従って次のアクション（タスク実行→report_completed）を実行してください。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ]
            ] as [String: Any],
            "required": ["session_token"]
        ]
    ]

    /// report_completed - タスク完了を報告
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    static let reportCompleted: [String: Any] = [
        "name": "report_completed",
        "description": "タスク完了を報告します。resultには 'success', 'failed', 'blocked' のいずれかを指定します。成功時はタスクがdoneに、失敗・ブロック時はblockedに変更されます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "result": [
                    "type": "string",
                    "description": "実行結果",
                    "enum": ["success", "failed", "blocked"]
                ],
                "summary": [
                    "type": "string",
                    "description": "作業サマリー（任意）"
                ],
                "next_steps": [
                    "type": "string",
                    "description": "次のステップ（任意）"
                ]
            ] as [String: Any],
            "required": ["session_token", "result"]
        ]
    ]

    // MARK: - Deprecated (Phase 3, use Phase 4 APIs instead)

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
    /// Phase 3-4: セッショントークン検証必須
    /// ⚠️ Phase 4で非推奨: get_my_task を使用してください
    static let getPendingTasks: [String: Any] = [
        "name": "get_pending_tasks",
        "description": "【非推奨: get_my_task を使用してください】認証済みエージェントの作業中（in_progress）タスク一覧を取得します。外部Runnerが作業継続のために使用します。セッショントークンで認証済みのエージェントのみ取得可能です。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ]
            ] as [String: Any],
            "required": ["session_token"]
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

    // MARK: - Execution Log Tools (Phase 3-3, Phase 4で非推奨)

    /// report_execution_start - 実行開始を報告
    /// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3
    /// Phase 3-4: セッショントークン検証必須
    /// ⚠️ Phase 4で非推奨: get_my_task呼び出し時に自動記録されます
    static let reportExecutionStart: [String: Any] = [
        "name": "report_execution_start",
        "description": "【非推奨: get_my_task呼び出し時に自動記録されます】タスク実行の開始を報告します。Runnerがタスク実行を開始した際に呼び出します。execution_log_idが返されるので、完了時にreport_execution_completeに渡してください。セッショントークンで認証が必要です。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "task_id": [
                    "type": "string",
                    "description": "実行するタスクID"
                ]
            ] as [String: Any],
            "required": ["session_token", "task_id"]
        ]
    ]

    /// report_execution_complete - 実行完了を報告
    /// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3
    /// Phase 3-4: セッショントークン検証必須
    /// ⚠️ Phase 4で非推奨: report_completed を使用してください
    static let reportExecutionComplete: [String: Any] = [
        "name": "report_execution_complete",
        "description": "【非推奨: report_completed を使用してください】タスク実行の完了を報告します。exit_codeが0なら成功、それ以外は失敗として記録されます。セッショントークンで認証が必要です。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "execution_log_id": [
                    "type": "string",
                    "description": "report_execution_startで取得した実行ログID"
                ],
                "exit_code": [
                    "type": "integer",
                    "description": "終了コード（0=成功、それ以外=失敗）"
                ],
                "duration_seconds": [
                    "type": "number",
                    "description": "実行時間（秒）"
                ],
                "log_file_path": [
                    "type": "string",
                    "description": "ログファイルのパス（任意）"
                ],
                "error_message": [
                    "type": "string",
                    "description": "エラーメッセージ（失敗時のみ）"
                ]
            ] as [String: Any],
            "required": ["session_token", "execution_log_id", "exit_code", "duration_seconds"]
        ]
    ]

    // MARK: - Phase 4: Coordinator用（認証不要）

    /// register_execution_log_file - 実行ログにログファイルパスを登録
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Coordinatorがプロセス完了後にログファイルパスを登録する際に使用
    /// 認証不要: Coordinatorは認証せずに直接呼び出す
    static let registerExecutionLogFile: [String: Any] = [
        "name": "register_execution_log_file",
        "description": "実行ログにログファイルパスを登録します。Coordinatorがプロセス完了後に呼び出します。認証不要。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID"
                ],
                "task_id": [
                    "type": "string",
                    "description": "タスクID"
                ],
                "log_file_path": [
                    "type": "string",
                    "description": "ログファイルの絶対パス"
                ]
            ] as [String: Any],
            "required": ["agent_id", "task_id", "log_file_path"]
        ]
    ]
}
