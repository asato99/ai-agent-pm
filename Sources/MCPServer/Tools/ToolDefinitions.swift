// Sources/MCPServer/Tools/ToolDefinitions.swift
// 参照: docs/prd/MCP_DESIGN.md - Tool定義（ステートレス設計）
// 参照: docs/architecture/MCP_SERVER.md - MCPサーバー設計

import Foundation

/// MCP Tool定義を提供
/// ステートレス設計: 必要なIDは全て引数として受け取る
enum ToolDefinitions {

    /// 全Tool一覧
    /// 参照: Sources/MCPServer/Authorization/ToolAuthorization.swift - 権限定義
    static func all() -> [[String: Any]] {
        [
            // ========================================
            // 未認証でも呼び出し可能
            // ========================================
            help,          // ヘルプ（利用可能ツール一覧）
            authenticate,

            // ========================================
            // Coordinator専用（coordinator_token必須）
            // ========================================
            healthCheck,
            listManagedAgents,
            listActiveProjectsWithAgents,
            getAgentAction,
            registerExecutionLogFile,
            invalidateSession,
            reportAgentError,

            // ========================================
            // Manager専用（session_token + hierarchy_type=manager）
            // ========================================
            listSubordinates,      // NEW: 下位エージェント一覧
            getSubordinateProfile, // NEW: 下位エージェント詳細
            createTask,
            createTasksBatch,      // NEW: 依存関係付き一括タスク作成
            assignTask,

            // ========================================
            // Worker専用（session_token + hierarchy_type=worker）
            // ========================================
            reportCompleted,

            // ========================================
            // 認証済み共通（Manager + Worker）
            // ========================================
            logout,            // セッション終了
            reportModel,
            getMyProfile,
            getMyTask,
            getNotifications,  // 通知取得
            getNextAction,
            updateTaskStatus,
            getProject,
            listTasks,
            getTask,
            reportExecutionStart,  // 非推奨（後方互換性のため維持）
            reportExecutionComplete,  // 非推奨（後方互換性のため維持）

            // ========================================
            // チャット機能（認証済み）
            // 参照: docs/design/CHAT_FEATURE.md
            // 参照: docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md
            // ========================================
            getPendingMessages,
            respondChat,
            sendMessage,  // タスク・チャット両方で使用可能

            // ========================================
            // AI-to-AI会話機能（認証済み）
            // 参照: docs/design/AI_TO_AI_CONVERSATION.md
            // ========================================
            startConversation,  // 会話開始
            endConversation,    // 会話終了

            // ========================================
            // 削除済み（権限なし - 呼び出し不可）
            // ========================================
            // - list_agents: → list_subordinates を使用
            // - get_agent_profile: → get_subordinate_profile を使用
            // - list_projects: → get_project を使用
            // - get_my_tasks: → list_tasks(assignee_id) を使用
            // - get_pending_tasks: → get_my_task を使用
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
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.3
    static let listActiveProjectsWithAgents: [String: Any] = [
        "name": "list_active_projects_with_agents",
        "description": "アクティブなプロジェクト一覧と、各プロジェクトに割り当てられたエージェントを取得します。Runnerがポーリング対象を決定するために使用します。agent_idを指定すると、そのエージェントのマルチデバイス用ワーキングディレクトリ設定を参照してworking_directoryを解決します。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "（オプション）マルチデバイス対応のためにワーキングディレクトリを解決するエージェントID。指定しない場合はプロジェクトのデフォルトworking_directoryを使用。"
                ] as [String: Any]
            ] as [String: Any],
            "required": [] as [String]
        ]
    ]

    /// get_agent_action - エージェントが取るべきアクションを返す
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Coordinatorはタスクの詳細を知らない。action（start/hold/stop/restart）と reason を返す。
    /// Phase 4: project_idを追加（(agent_id, project_id)単位で判断）
    static let getAgentAction: [String: Any] = [
        "name": "get_agent_action",
        "description": "エージェントが取るべきアクション（start/hold/stop/restart）を判定します。Coordinatorが使用します。タスク詳細は返さず、アクション判断のみを提供します。action='start'の場合はエージェントを起動、'hold'の場合は現状維持です。",
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
        ] as [String: Any]
    ]

    // MARK: - Logout（認証済みエージェント用）

    /// logout - セッションを終了
    /// 認証済みエージェントがセッションを明示的に終了する際に使用
    /// チャット完了後などにget_next_actionから指示される
    static let logout: [String: Any] = [
        "name": "logout",
        "description": "現在のセッションを終了します。チャット応答完了後など、get_next_actionから「logout」アクションが指示された場合に呼び出してください。セッション終了後、エージェントプロセスを終了してください。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["session_token"]
        ] as [String: Any]
    ]

    // MARK: - Help（未認証でも利用可能）
    // 参照: docs/design/TOOL_AUTHORIZATION_ENHANCEMENT.md

    /// helpツール定義
    /// 利用可能なMCPツールの一覧と詳細を表示
    /// 呼び出し元の認証状態とセッションのpurposeに応じて表示内容が変わる
    static let help: [String: Any] = [
        "name": "help",
        "description": "利用可能なMCPツールの一覧と詳細を表示します。呼び出し元の認証状態とセッションのpurpose（task/chat）に応じて、実際に利用可能なツールのみが表示されます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "tool_name": [
                    "type": "string",
                    "description": "特定のツール名を指定すると、そのツールの詳細（パラメータ、使用例）を表示します。省略すると利用可能なツール一覧を表示します。"
                ] as [String: Any]
            ] as [String: Any],
            "required": [] as [String]
        ] as [String: Any]
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

    /// get_notifications - 未読通知を取得
    /// 参照: docs/design/NOTIFICATION_SYSTEM.md
    static let getNotifications: [String: Any] = [
        "name": "get_notifications",
        "description": "未読通知を取得します。通知にはステータス変更、割り込み指示、メッセージが含まれます。interrupt タイプの通知を受信した場合は、instruction に従って即座に対応してください。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "mark_as_read": [
                    "type": "boolean",
                    "description": "取得と同時に既読にするかどうか（デフォルト: true）"
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

    /// get_next_action - 次のアクションを取得（状態駆動ワークフロー制御）
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Agent Instanceが定期的に呼び出し、現在の状態に応じた指示を取得
    static let getNextAction: [String: Any] = [
        "name": "get_next_action",
        "description": "次に実行すべきアクションを取得します。Agent Instanceは作業ループ内で定期的にこのツールを呼び出し、返された指示に従ってください。状態に応じて適切な次のステップ（モデル申告、タスク取得、サブタスク作成、サブタスク実行、完了報告など）が指示されます。",
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

    /// report_model - 使用中のモデル情報を申告
    /// Agent Instanceが自身のプロバイダーとモデルIDを申告するために使用
    /// App側で期待モデルとの照合を行い、検証結果をセッションに記録
    static let reportModel: [String: Any] = [
        "name": "report_model",
        "description": "Agent Instanceが使用中のプロバイダーとモデルIDを申告します。Appは申告内容をエージェント設定と照合し、検証結果をセッションに記録します。get_next_actionで'report_model'アクションが指示された場合に呼び出してください。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "provider": [
                    "type": "string",
                    "description": "使用中のプロバイダー名（claude, gemini, openai, custom など）"
                ],
                "model_id": [
                    "type": "string",
                    "description": "使用中のモデルID。バージョンを含む完全な名前を指定してください（例: claude-sonnet-4-5-20250929, claude-opus-4-20250514, gemini-2.5-pro, gpt-4o）"
                ]
            ] as [String: Any],
            "required": ["session_token", "provider", "model_id"]
        ]
    ]

    // MARK: - Manager-Only Tools (Phase 5: Authorization)

    /// list_subordinates - マネージャーの下位エージェント一覧を取得
    /// 参照: Sources/MCPServer/Authorization/ToolAuthorization.swift
    /// マネージャーのみ呼び出し可能。自身のparentAgentIdを持つエージェントのみ返す。
    static let listSubordinates: [String: Any] = [
        "name": "list_subordinates",
        "description": "自分の下位エージェント（ワーカー）一覧を取得します。マネージャーのみ呼び出し可能です。各エージェントのID、名前、役割、現在のステータスが含まれます。",
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

    /// get_subordinate_profile - 下位エージェントの詳細情報を取得
    /// 参照: Sources/MCPServer/Authorization/ToolAuthorization.swift
    /// マネージャーのみ呼び出し可能。自身の下位エージェントの詳細情報（プロンプト等）を取得。
    static let getSubordinateProfile: [String: Any] = [
        "name": "get_subordinate_profile",
        "description": "指定した下位エージェントの詳細情報を取得します。マネージャーのみ呼び出し可能で、自分の下位エージェントのみ指定できます。ID、名前、役割、システムプロンプト、設定が含まれます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "agent_id": [
                    "type": "string",
                    "description": "取得する下位エージェントのID"
                ]
            ] as [String: Any],
            "required": ["session_token", "agent_id"]
        ]
    ]

    // MARK: - Authenticated Tools (Manager + Worker)

    /// get_my_profile - 自身のエージェント情報を取得
    /// 認証済みエージェント（Manager/Worker）が呼び出し可能
    static let getMyProfile: [String: Any] = [
        "name": "get_my_profile",
        "description": "自分のエージェント情報を取得します。エージェントID、名前、役割、タイプが含まれます。",
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

    // MARK: - Project Tools

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

    /// get_task - タスク詳細を取得（認証必須）
    /// 認証済みエージェント（Manager/Worker）が呼び出し可能
    static let getTask: [String: Any] = [
        "name": "get_task",
        "description": "指定したタスクの詳細情報を取得します。最新のコンテキストも含まれます。認証が必要です。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "task_id": [
                    "type": "string",
                    "description": "タスクID"
                ]
            ] as [String: Any],
            "required": ["session_token", "task_id"]
        ]
    ]

    /// create_task - 新規タスク作成（サブタスク作成用）
    /// Agent Instanceがメインタスクをサブタスクに分解する際に使用
    static let createTask: [String: Any] = [
        "name": "create_task",
        "description": "新しいタスクを作成します。セッショントークンで認証されたエージェントがサブタスクを作成する際に使用します。作成されたタスクは自動的に現在のプロジェクトに紐づき、作成者に割り当てられます。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "title": [
                    "type": "string",
                    "description": "タスクタイトル"
                ],
                "description": [
                    "type": "string",
                    "description": "タスク詳細"
                ],
                "priority": [
                    "type": "string",
                    "description": "優先度",
                    "enum": ["low", "medium", "high", "urgent"]
                ],
                "parent_task_id": [
                    "type": "string",
                    "description": "親タスクID（サブタスク作成時に指定）"
                ],
                "dependencies": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "依存タスクIDの配列（このタスクは指定されたタスクが完了するまで開始できない）"
                ]
            ] as [String: Any],
            "required": ["session_token", "title", "description"]
        ]
    ]

    /// create_tasks_batch - 複数タスクを依存関係付きで一括作成
    /// ローカル参照ID（local_id）を使って、バッチ内でタスク間の依存関係を指定可能
    static let createTasksBatch: [String: Any] = [
        "name": "create_tasks_batch",
        "description": """
            複数のサブタスクを一括で作成します。各タスクにlocal_idを指定し、dependenciesでそのlocal_idを参照することで、
            バッチ内のタスク間の依存関係を設定できます。システムがlocal_idを実際のタスクIDに解決します。
            """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "parent_task_id": [
                    "type": "string",
                    "description": "親タスクID（全てのサブタスクに共通）"
                ],
                "tasks": [
                    "type": "array",
                    "description": "作成するタスクの配列",
                    "items": [
                        "type": "object",
                        "properties": [
                            "local_id": [
                                "type": "string",
                                "description": "バッチ内でこのタスクを参照するためのローカルID（例: 'task_1', 'generator'）"
                            ],
                            "title": [
                                "type": "string",
                                "description": "タスクタイトル"
                            ],
                            "description": [
                                "type": "string",
                                "description": "タスク詳細"
                            ],
                            "priority": [
                                "type": "string",
                                "description": "優先度",
                                "enum": ["low", "medium", "high", "urgent"]
                            ],
                            "dependencies": [
                                "type": "array",
                                "items": ["type": "string"],
                                "description": "依存タスクのlocal_id配列（バッチ内の他タスクを参照）"
                            ]
                        ] as [String: Any],
                        "required": ["local_id", "title", "description"]
                    ] as [String: Any]
                ]
            ] as [String: Any],
            "required": ["session_token", "parent_task_id", "tasks"]
        ]
    ]

    /// update_task_status - タスクのステータスを更新
    /// Phase 4: session_token必須（権限チェック）
    static let updateTaskStatus: [String: Any] = [
        "name": "update_task_status",
        "description": "タスクのステータスを更新します。ステータス遷移ルールに従う必要があります。自分が担当するタスクまたはサブタスクのみ更新可能です。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "認証で取得したセッショントークン"
                ],
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
            "required": ["session_token", "task_id", "status"]
        ]
    ]

    /// assign_task - タスク割り当て（マネージャー専用）
    static let assignTask: [String: Any] = [
        "name": "assign_task",
        "description": "タスクを指定のエージェントに割り当てます。マネージャーのみが呼び出し可能で、自身の下位エージェントにのみ割り当てできます。assignee_idを省略すると割り当て解除になります。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "セッショントークン（authenticate で取得）"
                ],
                "task_id": [
                    "type": "string",
                    "description": "割り当てるタスクのID"
                ],
                "assignee_id": [
                    "type": "string",
                    "description": "担当者のエージェントID（自身の下位エージェントのみ指定可能、省略で割り当て解除）"
                ]
            ] as [String: Any],
            "required": ["session_token", "task_id"]
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

    /// invalidate_session - セッションを無効化
    /// Coordinatorがエージェントプロセス終了時に呼び出します。
    /// 認証不要（Coordinator用API）。
    static let invalidateSession: [String: Any] = [
        "name": "invalidate_session",
        "description": "指定されたエージェント・プロジェクトのセッションを無効化します。Coordinatorがエージェントプロセス終了時に呼び出します。認証不要。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID"
                ],
                "project_id": [
                    "type": "string",
                    "description": "プロジェクトID"
                ]
            ] as [String: Any],
            "required": ["agent_id", "project_id"]
        ]
    ]

    /// report_agent_error - エージェントエラーをチャットに報告
    /// Coordinatorがエージェントプロセスがエラー終了した時に呼び出します。
    /// 認証不要（Coordinator用API）。
    static let reportAgentError: [String: Any] = [
        "name": "report_agent_error",
        "description": "エージェントのエラーをチャットに報告します。Coordinatorがエージェントプロセスのエラー終了時に呼び出します。認証不要。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "エージェントID"
                ],
                "project_id": [
                    "type": "string",
                    "description": "プロジェクトID"
                ],
                "error_message": [
                    "type": "string",
                    "description": "エラーメッセージ"
                ]
            ] as [String: Any],
            "required": ["agent_id", "project_id", "error_message"]
        ]
    ]

    // MARK: - Chat Tools
    // 参照: docs/design/CHAT_FEATURE.md - MCP連携設計

    /// get_pending_messages - 未読チャットメッセージを取得
    /// Agent Instance用: purpose=chatのセッションでのみ使用
    /// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 3
    static let getPendingMessages: [String: Any] = [
        "name": "get_pending_messages",
        "description": """
        未読のユーザーチャットメッセージを取得します。チャット目的で起動されたエージェントが最初に呼び出し、ユーザーからのメッセージを取得します。

        返り値:
        - context_messages: 文脈理解用の直近メッセージ（最大20件、user/agent両方含む）
        - pending_messages: 応答対象の未読メッセージ（最大10件）
        - total_history_count: 全履歴の件数
        - context_truncated: コンテキストが切り詰められたかどうか
        """,
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

    /// respond_chat - チャット応答を保存
    /// Agent Instance用: ユーザーメッセージに対する応答を保存
    /// target_agent_idを指定することで、メッセージリレーなど特定エージェントへの送信が可能
    static let respondChat: [String: Any] = [
        "name": "respond_chat",
        "description": "チャットメッセージに対する応答を保存します。get_pending_messagesで取得したメッセージに対して応答する際に使用します。target_agent_idを指定すると特定のエージェントに送信できます（リレーシナリオ用）。",
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "content": [
                    "type": "string",
                    "description": "応答メッセージの内容"
                ],
                "target_agent_id": [
                    "type": "string",
                    "description": "送信先エージェントID（省略時は未読メッセージの送信者に返信）。メッセージリレーの場合は明示的に送信先のエージェントIDを指定"
                ]
            ] as [String: Any],
            "required": ["session_token", "content"]
        ]
    ]

    /// send_message - プロジェクト内の他のエージェントにメッセージを送信
    /// 参照: docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md
    /// 参照: docs/design/AI_TO_AI_CONVERSATION.md - AI間メッセージ制約
    /// タスクセッション・チャットセッションの両方で使用可能（.authenticated権限）
    static let sendMessage: [String: Any] = [
        "name": "send_message",
        "description": """
            プロジェクト内の他のエージェントにメッセージを送信します（非同期）。
            受信者は get_pending_messages またはチャット画面で確認できます。
            タスクセッション・チャットセッションの両方で使用可能です。

            【重要】AIエージェント間のメッセージ送信には、アクティブな会話が必要です。
            先にstart_conversationで会話を開始してください。
            Human-AI間のメッセージにはこの制約はありません。
            """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "target_agent_id": [
                    "type": "string",
                    "description": "送信先エージェントID（同一プロジェクト内のエージェントのみ指定可能）"
                ],
                "content": [
                    "type": "string",
                    "description": "メッセージ内容（最大4,000文字）"
                ],
                "related_task_id": [
                    "type": "string",
                    "description": "関連タスクID（任意）"
                ],
                "conversation_id": [
                    "type": "string",
                    "description": "会話ID（AI-to-AI会話の場合に指定、省略時はアクティブ会話から自動設定）"
                ]
            ] as [String: Any],
            "required": ["session_token", "target_agent_id", "content"]
        ]
    ]

    // MARK: - AI-to-AI Conversation Tools
    // 参照: docs/design/AI_TO_AI_CONVERSATION.md

    /// start_conversation - 他のエージェントとの会話を開始
    /// 参照: docs/design/AI_TO_AI_CONVERSATION.md - start_conversation ツール
    static let startConversation: [String: Any] = [
        "name": "start_conversation",
        "description": """
            他のAIエージェントとの明示的な会話を開始します。
            相手エージェントが認証後、get_next_actionで会話要求を受信し、activeになります。
            会話終了時はend_conversationを呼び出してください。
            max_turnsで指定したターン数を超えると会話は自動終了します。
            """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "participant_agent_id": [
                    "type": "string",
                    "description": "会話相手のエージェントID（同一プロジェクト内のエージェントのみ）"
                ],
                "purpose": [
                    "type": "string",
                    "description": "会話の目的（任意、相手への説明用）"
                ],
                "initial_message": [
                    "type": "string",
                    "description": "最初のメッセージ内容（最大4,000文字）"
                ],
                "max_turns": [
                    "type": "integer",
                    "description": "最大ターン数（1メッセージ = 1ターン）。デフォルト20（10往復）、上限40（20往復）。超過すると会話は自動終了します。"
                ]
            ] as [String: Any],
            "required": ["session_token", "participant_agent_id", "initial_message", "max_turns"]
        ]
    ]

    /// end_conversation - 会話を終了
    /// 参照: docs/design/AI_TO_AI_CONVERSATION.md - end_conversation ツール
    static let endConversation: [String: Any] = [
        "name": "end_conversation",
        "description": """
            AI-to-AI会話を終了します。
            会話はterminatingに遷移し、相手エージェントがget_next_actionで終了通知を受信後、endedになります。
            会話の両参加者のどちらからでも終了可能です。
            """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "session_token": [
                    "type": "string",
                    "description": "authenticateツールで取得したセッショントークン"
                ],
                "conversation_id": [
                    "type": "string",
                    "description": "終了する会話のID"
                ],
                "final_message": [
                    "type": "string",
                    "description": "終了時の最終メッセージ（任意、最大4,000文字）"
                ]
            ] as [String: Any],
            "required": ["session_token", "conversation_id"]
        ]
    ]
}
