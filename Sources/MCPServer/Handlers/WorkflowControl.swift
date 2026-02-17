// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - State-Driven Workflow Control

extension MCPServer {

    // MARK: Phase 4: State-Driven Workflow Control

    /// get_next_action - 状態駆動ワークフロー制御
    /// 参照: docs/plan/STATE_DRIVEN_WORKFLOW.md
    /// Agent の hierarchy_type と Context のワークフローフェーズに基づいて次のアクションを判断
    /// モデル検証が未完了の場合は report_model アクションを返す
    func getNextAction(session: AgentSession) throws -> [String: Any] {
        let agentId = session.agentId
        let projectId = session.projectId
        Self.log("[MCP] getNextAction called for agent: '\(agentId.value)', project: '\(projectId.value)'")

        // 1. エージェント情報を取得（hierarchy_type 判断用）
        guard let agent = try agentRepository.findById(agentId) else {
            Self.log("[MCP] getNextAction: Agent not found: \(agentId.value)")
            return [
                "action": "error",
                "instruction": "エージェントが見つかりません。",
                "error": "agent_not_found"
            ]
        }

        // 1.5. モデル検証チェック - 未検証の場合は report_model を要求
        if session.modelVerified == nil {
            Self.log("[MCP] getNextAction: Model not verified yet, requesting report_model")
            return [
                "action": "report_model",
                "instruction": """
                    モデル情報を申告してください。
                    report_model ツールを呼び出し、現在使用中の provider と model_id を申告してください。

                    - provider: "claude", "gemini", "openai" などのプロバイダー名
                    - model_id: 使用中のモデル名（例: "claude-sonnet-4-5", "gemini-2.5-pro", "gpt-4o"）

                    ※ model_id は使用中のモデル名を申告してください。
                    申告後、get_next_action を再度呼び出してください。
                    """,
                "state": "needs_model_verification"
            ]
        }

        // 1.6. UC015: セッション終了チェック - terminating 状態なら exit を返す
        // 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6
        if session.state == .terminating {
            Self.log("[MCP] getNextAction: Session is terminating, returning exit action")
            return [
                "action": "exit",
                "instruction": """
                    ユーザーがチャットを閉じました。
                    logout を呼び出してセッションを終了してください。
                    """,
                "state": "session_terminating",
                "reason": "user_closed_chat"
            ]
        }

        // 1.7. Chat機能: purpose=chat の場合はチャット応答フローへ
        if session.purpose == .chat {
            // セッションタイムアウトチェック（10分）
            // lastActivityAt からの経過時間を使用（アイドル時間ベース）
            let idleTime = Date().timeIntervalSince(session.lastActivityAt)
            let softTimeoutSeconds = 10.0 * 60.0  // 10分

            if idleTime > softTimeoutSeconds {
                Self.log("[MCP] getNextAction: Chat session soft timeout reached (\(Int(idleTime))s idle)")
                return [
                    "action": "logout",
                    "instruction": """
                        セッションがタイムアウトしました（10分経過）。
                        logout を呼び出してセッションを終了してください。
                        """,
                    "state": "chat_timeout",
                    "reason": "session_timeout"
                ]
            }

            // 1.7.1. AI-to-AI会話チェック（UC016）
            // 参照: docs/design/AI_TO_AI_CONVERSATION.md - getNextAction拡張
            // pending会話の検出（相手からの会話要求）
            let pendingConversations = try conversationRepository.findPendingForParticipant(
                session.agentId,
                projectId: session.projectId
            )
            if let pendingConv = pendingConversations.first {
                // 会話をactiveに遷移
                try conversationRepository.updateState(pendingConv.id, state: .active)
                Self.log("[MCP] getNextAction: Accepted conversation request: \(pendingConv.id.value)")

                return [
                    "action": "conversation_request",
                    "instruction": """
                        AI-to-AI会話の要求を受信しました。
                        相手エージェントからの会話を受け入れ、get_pending_messages でメッセージを取得してください。
                        会話を終了する場合は end_conversation を呼び出してください。
                        """,
                    "state": "conversation_active",
                    "conversation_id": pendingConv.id.value,
                    "initiator_agent_id": pendingConv.initiatorAgentId.value,
                    "purpose": pendingConv.purpose ?? ""
                ]
            }

            // terminatingの会話をチェック（相手が終了を要求）
            let activeConversations = try conversationRepository.findActiveByAgentId(
                session.agentId,
                projectId: session.projectId
            )
            for conv in activeConversations {
                // 自分がparticipantで、会話がterminatingの場合
                if let terminatingConv = try conversationRepository.findById(conv.id),
                   terminatingConv.state == .terminating {
                    // 会話をendedに遷移
                    try conversationRepository.updateState(terminatingConv.id, state: .ended, endedAt: Date())
                    Self.log("[MCP] getNextAction: Conversation ended by partner: \(terminatingConv.id.value)")

                    return [
                        "action": "conversation_ended",
                        "instruction": """
                            AI-to-AI会話が終了しました。
                            相手エージェントが会話を終了しました。
                            未読メッセージがあれば処理し、get_next_action で次のアクションを確認してください。
                            """,
                        "state": "conversation_ended",
                        "conversation_id": terminatingConv.id.value,
                        "ended_by": terminatingConv.getPartnerId(for: session.agentId)?.value ?? ""
                    ]
                }
            }

            // pending委譲があるかチェック（タスクセッションからの依頼）
            // 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
            let pendingDelegations = try chatDelegationRepository.findPendingByAgentId(
                session.agentId,
                projectId: session.projectId
            )

            if let delegation = pendingDelegations.first {
                // pending委譲がある = 他エージェントとの会話を開始する
                Self.log("[MCP] getNextAction: Chat session has pending delegation to \(delegation.targetAgentId.value), directing to start_conversation")
                // 委譲をprocessingに更新
                try chatDelegationRepository.updateStatus(delegation.id, status: .processing)
                return [
                    "action": "start_conversation",
                    "instruction": """
                        タスクセッションから他エージェントとの会話依頼があります。

                        【依頼内容】
                        対象エージェント: \(delegation.targetAgentId.value)
                        目的: \(delegation.purpose)
                        \(delegation.context.map { "コンテキスト: \($0)" } ?? "")

                        start_conversation ツールを使用して、対象エージェントとの会話を開始してください。
                        引数:
                        - participant_agent_id: "\(delegation.targetAgentId.value)"
                        - purpose: "\(delegation.purpose)"
                        - initial_message: 目的に沿った最初のメッセージを作成してください

                        会話が完了したら、report_delegation_completed ツールで結果を報告してください。
                        """,
                    "state": "process_delegation",
                    "delegation_id": delegation.id.value,
                    "target_agent_id": delegation.targetAgentId.value,
                    "purpose": delegation.purpose,
                    "context": delegation.context as Any
                ]
            }

            // 未読メッセージがあるか確認してからアクションを決定
            let pendingMessages = try chatRepository.findUnreadMessages(
                projectId: session.projectId,
                agentId: session.agentId
            )

            if pendingMessages.isEmpty {
                // 未読メッセージなし = 待機モードへ（セッション維持）
                // Note: 2秒間隔でポーリングして、5秒以内の応答を実現する
                let remainingMinutes = Int((softTimeoutSeconds - idleTime) / 60)
                Self.log("[MCP] getNextAction: Chat session with no pending messages, waiting for messages (remaining: \(remainingMinutes)min)")
                return [
                    "action": "wait_for_messages",
                    "instruction": """
                        現在処理待ちのメッセージがありません。
                        2秒後に再度 get_next_action を呼び出して新しいメッセージを確認してください。

                        【重要】チャットセッションの役割
                        - ユーザーとの対話、質問への回答、タスク依頼の受付のみを行います
                        - 実際の作業はタスクセッションで別途実行されます

                        作業依頼を受けた場合は request_task でタスク登録してください。
                        """,
                    "state": "chat_waiting",
                    "wait_seconds": 2,
                    "remaining_timeout_minutes": remainingMinutes
                ]
            } else {
                Self.log("[MCP] getNextAction: Chat session detected with \(pendingMessages.count) pending message(s), directing to get_pending_messages")
                return [
                    "action": "get_pending_messages",
                    "instruction": """
                        チャットセッションです。
                        get_pending_messages を呼び出して未読メッセージを取得してください。

                        【重要】チャットセッションの役割
                        - 他エージェントとの対話、質問への回答、タスク依頼の受付のみを行います
                        - 実際の作業（コード実装、テスト実行、ファイル作成など）は行いません
                        - 作業はタスクセッションで別途実行されます

                        【チャットコマンド】受信メッセージの @@マーカー に応じて適切なツールを使用してください:
                        名前付き引数は --key value 形式で指定されます。省略された引数はあなたが判断してください。

                        ■ @@タスク作成: タイトル [--priority low|medium|high|urgent] [--description "説明"] [--parent タスクID]
                          → request_task(title, description?, priority?, parent_task_id?) で新規タスク作成
                          → 引数省略時の判断:
                            ・priority: メッセージ内容から緊急度を判断（デフォルト: medium）
                            ・description: メッセージ本文から補足があれば設定
                          → 応答例: 「ご依頼を承りました。タスクを登録しました」

                        ■ @@タスク通知: メッセージ [--task タスクID] [--priority low|normal|high]
                          → notify_task_session(message, related_task_id?, priority?) で既存タスクセッションに通知
                          → 引数省略時: 会話の文脈から関連タスクを特定、優先度はデフォルト normal
                          → 応答例: 「タスクセッションに通知しました」

                        ■ @@タスク調整: 調整内容 [--task タスクID] [--status ステータス] [--description "説明"]
                          → update_task_from_chat(task_id, requester_id, description?, status?) で既存タスクの修正・削除
                          → 引数省略時: list_tasks で対象タスクを特定、status/description は調整内容から推測
                          → 応答例: 「タスクを更新しました」

                        ■ @@タスク開始: タスクID
                          → start_task_from_chat(task_id: "タスクID") でbacklog/todoのタスクを実行開始(in_progress)
                          → 応答例: 「タスクの実行を開始しました」

                        ■ マーカーなし
                          → 作業依頼や通知・調整の意図がある場合:
                            「以下のマーカーをつけてお送りください:
                             ・新規タスク作成: @@タスク作成: タイトル [--priority 優先度]
                             ・既存タスクへの通知: @@タスク通知: メッセージ [--task ID]
                             ・既存タスクの修正/削除: @@タスク調整: 内容 [--task ID]
                             ・タスクの実行開始: @@タスク開始: タスクID」と案内
                          → 単なる質問や相談: send_message で通常応答

                        【注意】タスク関連のコマンドを実行する前に、既存のタスク一覧・状況を確認し、
                        新規作成・通知・調整・開始のどれが適切かを判断してください。
                        重複タスクの作成や、存在しないタスクへの操作を防ぐためです。

                        【使用できないツール】
                        create_task, update_task_status などのタスク操作ツールはチャットセッションでは使用できません。
                        """,
                    "state": "chat_session"
                ]
            }
        }

        // 2. メインタスク（in_progress 状態）を取得
        // 階層タイプによって検索方法が異なる:
        // - Manager: トップレベルタスク（parentTaskId == nil）を所有
        // - Worker: 直接割り当てタスクまたは委任されたサブタスク（parentTaskId != nil の場合もある）
        let allTasks = try taskRepository.findByAssignee(agentId)
        let inProgressTasks = allTasks.filter { $0.status == .inProgress && $0.projectId == projectId }

        let mainTask: Task?
        switch agent.hierarchyType {
        case .manager:
            // Manager はトップレベルタスクを所有
            mainTask = inProgressTasks.first { $0.parentTaskId == nil }
        case .worker:
            // Worker は直接割り当てタスクまたは Manager から委任されたサブタスクを持つ
            // parentTaskId の有無は関係ない
            mainTask = inProgressTasks.first
        }

        guard let main = mainTask else {
            // メインタスクがない = get_my_task をまだ呼んでいない
            // Coordinator は in_progress タスクがある場合のみ起動するので、
            // ここに来るのは get_my_task 呼び出し前のみ
            return [
                "action": "get_task",
                "instruction": """
                    get_my_task を呼び出してタスク詳細を取得してください。
                    取得後、get_next_action を呼び出して次の指示を受けてください。
                    タスクの description を直接実行しないでください。
                    その他の可能な操作は help ツールで確認できます。
                    """,
                "state": "needs_task"
            ]
        }

        // 3. Context から最新のワークフローフェーズを取得
        let latestContext = try contextRepository.findLatest(taskId: main.id)
        let phase = latestContext?.progress ?? ""

        Self.log("[MCP] getNextAction: hierarchy=\(agent.hierarchyType.rawValue), phase=\(phase)")

        // 4. 階層タイプに応じた処理を分岐
        switch agent.hierarchyType {
        case .worker:
            return try getWorkerNextAction(mainTask: main, phase: phase, allTasks: allTasks)
        case .manager:
            return try getManagerNextAction(mainTask: main, phase: phase, allTasks: allTasks, session: session)
        }
    }

    /// get_next_action - Long Polling 対応非同期版
    /// 参照: docs/design/CHAT_LONG_POLLING.md
    /// チャットセッションの場合、新しいメッセージが到着するかタイムアウトまでサーバーサイドで待機
    /// これによりGemini APIのレート制限を回避しつつリアルタイムなチャット体験を維持
    func getNextActionAsync(session: AgentSession, timeoutSeconds: Int) async throws -> [String: Any] {
        let agentId = session.agentId
        let projectId = session.projectId
        Self.log("[MCP] getNextActionAsync called for agent: '\(agentId.value)', project: '\(projectId.value)', timeout: \(timeoutSeconds)s")

        // チャットセッション以外は同期版にフォールバック
        guard session.purpose == .chat else {
            Self.log("[MCP] getNextActionAsync: Not a chat session, falling back to sync version")
            return try getNextAction(session: session)
        }

        // モデル検証チェック
        if session.modelVerified == nil {
            return try getNextAction(session: session)
        }

        // セッション終了チェック
        if session.state == .terminating {
            return try getNextAction(session: session)
        }

        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        let checkInterval: UInt64 = 1_000_000_000  // 1秒（ナノ秒）
        let softTimeoutSeconds = 10.0 * 60.0  // 10分

        // Long Polling: メッセージが来るかタイムアウトまで待機
        while Date() < deadline {
            // 1. セッションタイムアウトチェック
            let idleTime = Date().timeIntervalSince(session.lastActivityAt)
            if idleTime > softTimeoutSeconds {
                Self.log("[MCP] getNextActionAsync: Chat session soft timeout reached (\(Int(idleTime))s idle)")
                return [
                    "action": "logout",
                    "instruction": """
                        セッションがタイムアウトしました（10分経過）。
                        logout を呼び出してセッションを終了してください。
                        """,
                    "state": "chat_timeout",
                    "reason": "session_timeout"
                ]
            }

            // 2. セッション状態の再チェック（terminatingになったら即座に終了）
            if let currentSession = try? agentSessionRepository.findByToken(session.token),
               currentSession.state == .terminating {
                Self.log("[MCP] getNextActionAsync: Session is terminating, returning exit action")
                return [
                    "action": "exit",
                    "instruction": """
                        ユーザーがチャットを閉じました。
                        logout を呼び出してセッションを終了してください。
                        """,
                    "state": "session_terminating",
                    "reason": "user_closed_chat"
                ]
            }

            // 3. 未読メッセージのチェック
            let pendingMessages = try chatRepository.findUnreadMessages(
                projectId: projectId,
                agentId: agentId
            )

            if !pendingMessages.isEmpty {
                Self.log("[MCP] getNextActionAsync: \(pendingMessages.count) pending message(s) found, returning get_pending_messages")
                return [
                    "action": "get_pending_messages",
                    "instruction": """
                        チャットセッションです。
                        get_pending_messages を呼び出して未読メッセージを取得してください。

                        【チャットコマンド】受信メッセージの @@マーカー に応じて適切なツールを使用してください:
                        名前付き引数は --key value 形式で指定されます。省略された引数はあなたが判断してください。

                        ■ @@タスク作成: タイトル [--priority low|medium|high|urgent] [--description "説明"] [--parent タスクID]
                          → request_task(title, description?, priority?, parent_task_id?) で新規タスク作成
                          → 引数省略時の判断:
                            ・priority: メッセージ内容から緊急度を判断（デフォルト: medium）
                            ・description: メッセージ本文から補足があれば設定
                          → send_message で「ご依頼を承りました。タスクを登録し、承認待ちの状態です」と応答

                        ■ @@タスク通知: メッセージ [--task タスクID] [--priority low|normal|high]
                          → notify_task_session(message, related_task_id?, priority?) で既存タスクセッションに通知
                          → 引数省略時: 会話の文脈から関連タスクを特定、優先度はデフォルト normal
                          → send_message で「タスクセッションに通知しました」と応答

                        ■ @@タスク調整: 調整内容 [--task タスクID] [--status ステータス] [--description "説明"]
                          → update_task_from_chat(task_id, requester_id, description?, status?) で既存タスクの修正・削除
                          → 引数省略時: list_tasks で対象タスクを特定、status/description は調整内容から推測
                          → send_message で「タスクを更新しました」と応答

                        ■ @@タスク開始: タスクID
                          → start_task_from_chat(task_id: "タスクID") でbacklog/todoのタスクを実行開始(in_progress)
                          → send_message で「タスクの実行を開始しました」と応答

                        ■ マーカーなし
                          → 作業依頼・通知・調整・開始の意図がある場合は @@マーカーの案内をしてください
                          → 単なる質問や相談: send_message で通常応答

                        【注意】タスク関連のコマンドを実行する前に、既存のタスク一覧・状況を確認し、
                        新規作成・通知・調整・開始のどれが適切かを判断してください。

                        他のAIエージェントと会話する場合は start_conversation で開始し、end_conversation で終了します。
                        その他の可能な操作は help ツールで確認できます。
                        """,
                    "state": "chat_session"
                ]
            }

            // 4. AI-to-AI会話のチェック（未読メッセージがない場合のみ）
            let pendingConversations = try conversationRepository.findPendingForParticipant(
                agentId,
                projectId: projectId
            )
            if let pendingConv = pendingConversations.first {
                // 会話をactiveに遷移
                try conversationRepository.updateState(pendingConv.id, state: .active)
                Self.log("[MCP] getNextActionAsync: Accepted conversation request: \(pendingConv.id.value)")

                return [
                    "action": "conversation_request",
                    "instruction": """
                        AI-to-AI会話の要求を受信しました。
                        相手エージェントからの会話を受け入れ、get_pending_messages でメッセージを取得してください。
                        会話を終了する場合は end_conversation を呼び出してください。
                        """,
                    "state": "conversation_active",
                    "conversation_id": pendingConv.id.value,
                    "initiator_agent_id": pendingConv.initiatorAgentId.value,
                    "purpose": pendingConv.purpose ?? ""
                ]
            }

            // 5. 待機（CPU負荷なし）
            // Note: Domain.Task と衝突するため _Concurrency.Task を明示的に使用
            try await _Concurrency.Task.sleep(nanoseconds: checkInterval)
        }

        // タイムアウト: 即座に再呼び出しを要求（Long Pollingなのでクライアント側待機は不要）
        let remainingMinutes = Int((softTimeoutSeconds - Date().timeIntervalSince(session.lastActivityAt)) / 60)
        Self.log("[MCP] getNextActionAsync: Timeout reached, returning wait_for_messages (remaining: \(remainingMinutes)min)")
        return [
            "action": "wait_for_messages",
            "instruction": """
                現在処理待ちのメッセージがありません。
                【待機不要】サーバー側でLong Polling待機済みです。すぐに get_next_action を呼び出してください。

                【チャットコマンド】受信メッセージの @@マーカー に応じて適切なツールを使用してください:
                ■ @@タスク作成: タイトル [--priority 優先度 --description "説明" --parent タスクID] → request_task
                ■ @@タスク通知: メッセージ [--task ID --priority 優先度] → notify_task_session
                ■ @@タスク調整: 内容 [--task ID --status ステータス] → update_task_from_chat
                ■ @@タスク開始: タスクID → start_task_from_chat
                ■ マーカーなし → 意図がある場合は @@マーカーの案内、質問は send_message で応答
                ※名前付き引数省略時は、タスク一覧・エージェント一覧を確認して自主的に判断してください。

                他のAIエージェントと会話する場合は start_conversation で開始し、end_conversation で終了します。
                その他の可能な操作は help ツールで確認できます。
                """,
            "state": "chat_waiting",
            "wait_seconds": 0,  // Long Polling: サーバー側で既に待機済みのためクライアント側待機は不要
            "remaining_timeout_minutes": remainingMinutes
        ]
    }

    /// Worker のワークフロー制御
    /// 参照: docs/plan/STATE_DRIVEN_WORKFLOW.md - Worker のワークフロー
    /// Worker はサブタスクを作成し、自分で順番に実行する
    func getWorkerNextAction(mainTask: Task, phase: String, allTasks: [Task]) throws -> [String: Any] {
        Self.log("[MCP] getWorkerNextAction: task=\(mainTask.id.value), phase=\(phase)")

        // サブタスク（parentTaskId = mainTask.id）を取得
        let subTasks = allTasks.filter { $0.parentTaskId == mainTask.id }
        let pendingSubTasks = subTasks.filter { $0.status == .todo || $0.status == .backlog }
        let inProgressSubTasks = subTasks.filter { $0.status == .inProgress }
        let completedSubTasks = subTasks.filter { $0.status == .done }
        let blockedSubTasks = subTasks.filter { $0.status == .blocked }

        Self.log("[MCP] getWorkerNextAction: subTasks=\(subTasks.count), pending=\(pendingSubTasks.count), inProgress=\(inProgressSubTasks.count), completed=\(completedSubTasks.count), blocked=\(blockedSubTasks.count)")

        // 委譲タスク判定: createdByAgentId != assigneeId → 他のエージェントから委譲されたタスク
        // 委譲タスクはサブタスクに分解できるが、自己作成タスクはさらに分解しない（無限ネスト防止）
        let isDelegatedTask: Bool
        if let createdBy = mainTask.createdByAgentId, let assignee = mainTask.assigneeId {
            isDelegatedTask = createdBy != assignee
        } else {
            // createdByAgentId が nil の場合は、既存データ（マイグレーション前）
            // 後方互換性のため parentTaskId == nil で判定
            isDelegatedTask = mainTask.parentTaskId == nil
        }
        Self.log("[MCP] getWorkerNextAction: isDelegatedTask=\(isDelegatedTask), createdBy=\(mainTask.createdByAgentId?.value ?? "nil"), assignee=\(mainTask.assigneeId?.value ?? "nil")")

        // 1. サブタスク未作成 → サブタスク作成フェーズへ
        // 委譲タスク（他のエージェントから割り当てられた）場合はサブタスク作成可能
        // 自己作成タスク（自分で作成した）場合は実際の作業を行うべき（無限ネスト防止）
        if phase == "workflow:task_fetched" && subTasks.isEmpty && isDelegatedTask {
            // サブタスク作成フェーズを記録
            // Note: Context.sessionId は sessions テーブルを参照するため、
            // 先に Session を作成してからその ID を使用する
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: mainTask.projectId,
                agentId: mainTask.assigneeId!,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)

            let context = Context(
                id: ContextID.generate(),
                taskId: mainTask.id,
                sessionId: workflowSession.id,
                agentId: mainTask.assigneeId!,
                progress: "workflow:creating_subtasks"
            )
            try contextRepository.save(context)

            return [
                "action": "create_subtasks",
                "instruction": """
                    タスクの複雑さを評価し、適切にサブタスクを作成してください（目安: 2〜5個）。
                    単純な場合は同一内容で1つ作成し即座に作業開始、
                    複雑な場合は明確な成果物単位で分解してください。
                    複数のサブタスクを作成する場合は create_tasks_batch ツールを使用してください。
                    parent_task_id には '\(mainTask.id.value)' を指定してください。
                    サブタスク作成後、get_next_action を呼び出してください。
                    """,
                "state": "needs_subtask_creation",
                "task": [
                    "id": mainTask.id.value,
                    "title": mainTask.title,
                    "description": mainTask.description
                ]
            ]
        }

        // 1.5. 自己作成タスク（自分で作成した）で子タスクがない場合
        // → 実際の作業を行う（さらなる分解は不要、無限ネスト防止）
        if !isDelegatedTask && subTasks.isEmpty {
            return [
                "action": "work",
                "instruction": """
                    このタスクを直接実行してください。
                    タスクの内容に従って作業を行い、完了したら
                    update_task_status で status を 'done' に変更してください。
                    """,
                "state": "execute_task",
                "task": [
                    "id": mainTask.id.value,
                    "title": mainTask.title,
                    "description": mainTask.description
                ]
            ]
        }

        // 2. サブタスクが存在する場合 → 順番に実行
        if !subTasks.isEmpty {
            // 全サブタスク完了 → メインタスク完了報告
            if completedSubTasks.count == subTasks.count {
                return [
                    "action": "report_completion",
                    "instruction": """
                        全てのサブタスクが完了しました。
                        report_completed を呼び出してメインタスクを完了してください。
                        result には 'success' を指定し、作業内容を summary に記載してください。
                        """,
                    "state": "needs_completion",
                    "task": [
                        "id": mainTask.id.value,
                        "title": mainTask.title
                    ],
                    "completed_subtasks": completedSubTasks.count
                ]
            }

            // 完了ゲート: blocked サブタスクがある場合の処理
            // 参照: docs/plan/BLOCKED_TASK_RECOVERY.md - Phase 1-5
            // 全サブタスクが完了済みまたはブロック状態で、未着手・進行中がない場合
            if !blockedSubTasks.isEmpty && pendingSubTasks.isEmpty && inProgressSubTasks.isEmpty {
                // ブロック種別ごとに分類
                var userBlockedTasks: [[String: Any]] = []
                var selfBlockedTasks: [[String: Any]] = []
                var otherBlockedTasks: [[String: Any]] = []

                for task in blockedSubTasks {
                    let taskInfo: [String: Any] = [
                        "id": task.id.value,
                        "title": task.title,
                        "blocked_reason": task.blockedReason ?? "理由未記載",
                        "blocked_by": task.statusChangedByAgentId?.value ?? "unknown"
                    ]

                    if let changedBy = task.statusChangedByAgentId {
                        if changedBy.isUserAction {
                            userBlockedTasks.append(taskInfo)
                        } else if changedBy == mainTask.assigneeId {
                            selfBlockedTasks.append(taskInfo)
                        } else {
                            otherBlockedTasks.append(taskInfo)
                        }
                    } else {
                        // nilは自己ブロック扱い（後方互換性）
                        selfBlockedTasks.append(taskInfo)
                    }
                }

                // Workerも全てのブロック状況を把握して対処を検討できる
                // 自己ブロック → 解除可能、ユーザー/他者ブロック → 解除不可だが上位への報告は必要
                return [
                    "action": "review_and_resolve_blocks",
                    "instruction": """
                        以下のサブタスクがブロック状態です。対処を検討してください。

                        【ブロック種別と対応】
                        ■ 自己ブロック（解除可能）:
                          - ブロック理由を確認してください
                          - 理由が解決済みなら update_task_status で 'in_progress' に変更して作業再開

                        ■ ユーザー/他者によるブロック（解除不可）:
                          - 解除する権限がありません
                          - メインタスクを blocked として報告し、上位（マネージャー）に委ねてください

                        【最終判断】
                        - 対処できない場合:
                          → メインタスク自体を blocked にして report_completed で報告
                          → result は 'blocked'、summary にブロック理由を記載
                        - 無理に続行せず、上位（マネージャー）に委ねてください
                        """,
                    "state": "needs_review",
                    "self_blocked_subtasks": selfBlockedTasks,
                    "user_blocked_subtasks": userBlockedTasks,
                    "other_blocked_subtasks": otherBlockedTasks,
                    "completed_subtasks": completedSubTasks.count,
                    "total_subtasks": subTasks.count,
                    "can_unblock_self": !selfBlockedTasks.isEmpty,
                    "has_unresolvable_blocks": !userBlockedTasks.isEmpty || !otherBlockedTasks.isEmpty
                ]
            }

            // 実行中のサブタスクがある → 続けて実行
            if let currentSubTask = inProgressSubTasks.first {
                return [
                    "action": "execute_subtask",
                    "instruction": """
                        現在のサブタスクを実行してください。
                        完了したら update_task_status で status を 'done' に変更してください。
                        """,
                    "state": "executing_subtask",
                    "current_subtask": [
                        "id": currentSubTask.id.value,
                        "title": currentSubTask.title,
                        "description": currentSubTask.description
                    ],
                    "progress": [
                        "completed": completedSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            }

            // 次のサブタスクを開始（依存関係を考慮）
            // 依存タスクが全て完了しているサブタスクのみを実行可能とする
            let completedTaskIds = Set(completedSubTasks.map { $0.id })
            let executableSubTasks = pendingSubTasks.filter { task in
                // 依存関係がないか、全ての依存タスクが完了している
                task.dependencies.isEmpty || task.dependencies.allSatisfy { completedTaskIds.contains($0) }
            }

            Self.log("[MCP] getWorkerNextAction: executableSubTasks=\(executableSubTasks.count) (filtered from \(pendingSubTasks.count) pending)")

            if let nextSubTask = executableSubTasks.first {
                return [
                    "action": "start_subtask",
                    "instruction": """
                        次のサブタスクを開始してください。
                        update_task_status で '\(nextSubTask.id.value)' のステータスを 'in_progress' に変更し、
                        作業を実行してください。
                        """,
                    "state": "start_next_subtask",
                    "next_subtask": [
                        "id": nextSubTask.id.value,
                        "title": nextSubTask.title,
                        "description": nextSubTask.description
                    ],
                    "progress": [
                        "completed": completedSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            }

            // 待機中のサブタスクはあるが、依存関係が満たされていない
            // → 循環依存または不正な依存関係の可能性
            if !pendingSubTasks.isEmpty {
                let waitingTasks = pendingSubTasks.map { task -> [String: Any] in
                    let unmetDeps = task.dependencies.filter { !completedTaskIds.contains($0) }
                    return [
                        "id": task.id.value,
                        "title": task.title,
                        "waiting_for": unmetDeps.map { $0.value }
                    ]
                }
                Self.log("[MCP] getWorkerNextAction: All pending subtasks have unmet dependencies")
                return [
                    "action": "dependency_deadlock",
                    "instruction": """
                        全ての待機中サブタスクに未完了の依存関係があります。
                        循環依存または不正な依存関係の可能性があります。

                        対処方法:
                        1. 依存関係を確認し、不要な依存を削除する
                        2. または、このタスク全体を blocked として報告し、
                           report_completed で result='blocked' を指定してください。
                        """,
                    "state": "dependency_deadlock",
                    "waiting_subtasks": waitingTasks,
                    "completed_subtasks": completedSubTasks.count,
                    "total_subtasks": subTasks.count
                ]
            }
        }

        // 3. サブタスク作成中フェーズ → 作成完了後の処理
        if phase == "workflow:creating_subtasks" && !subTasks.isEmpty {
            // サブタスク作成完了を記録
            // Note: Context.sessionId は sessions テーブルを参照するため、
            // 先に Session を作成してからその ID を使用する
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: mainTask.projectId,
                agentId: mainTask.assigneeId!,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)

            let context = Context(
                id: ContextID.generate(),
                taskId: mainTask.id,
                sessionId: workflowSession.id,
                agentId: mainTask.assigneeId!,
                progress: "workflow:subtasks_created"
            )
            try contextRepository.save(context)

            // 最初のサブタスクを開始
            if let firstSubTask = pendingSubTasks.first {
                return [
                    "action": "start_subtask",
                    "instruction": """
                        サブタスクの実行を開始してください。
                        update_task_status で '\(firstSubTask.id.value)' のステータスを 'in_progress' に変更し、
                        作業を実行してください。
                        """,
                    "state": "start_next_subtask",
                    "next_subtask": [
                        "id": firstSubTask.id.value,
                        "title": firstSubTask.title,
                        "description": firstSubTask.description
                    ]
                ]
            }
        }

        // フォールバック
        return [
            "action": "get_task",
            "instruction": "get_my_task を呼び出してタスク詳細を取得してください。",
            "state": "needs_task"
        ]
    }

    /// Manager のワークフロー制御
    /// 参照: docs/plan/STATE_DRIVEN_WORKFLOW.md - Manager のワークフロー
    /// Manager はサブタスクを作成して Worker に割り当て（自分では実行しない）
    func getManagerNextAction(mainTask: Task, phase: String, allTasks: [Task], session: AgentSession) throws -> [String: Any] {
        Self.log("[MCP] getManagerNextAction: task=\(mainTask.id.value), phase=\(phase)")

        // サブタスク（parentTaskId = mainTask.id）を取得
        // Note: allTasksはマネージャーに割り当てられたタスクのみ（findByAssignee）なので、
        // ワーカーに割り当てられたサブタスクは含まれない。
        // プロジェクト全体からサブタスクを検索する必要がある。
        let projectTasks = try taskRepository.findByProject(mainTask.projectId, status: nil)
        let subTasks = projectTasks.filter { $0.parentTaskId == mainTask.id }
        let pendingSubTasks = subTasks.filter { $0.status == .todo || $0.status == .backlog }
        let inProgressSubTasks = subTasks.filter { $0.status == .inProgress }
        let completedSubTasks = subTasks.filter { $0.status == .done }
        let blockedSubTasks = subTasks.filter { $0.status == .blocked }

        // 未割り当てサブタスク: assigneeが未設定(nil)、またはマネージャーに割り当てられたままの pending タスク
        // これらはまずワーカーへの割り当て（assignee変更）が必要
        let unassignedSubTasks = pendingSubTasks.filter { $0.assigneeId == nil || $0.assigneeId == mainTask.assigneeId }

        // ワーカー割り当て済みサブタスク: ワーカーに割り当て済みの pending タスク
        // 注意: assigneeIdがnilの場合は「ワーカー割り当て済み」ではない
        let workerAssignedSubTasks = pendingSubTasks.filter { $0.assigneeId != nil && $0.assigneeId != mainTask.assigneeId }

        // 実行可能サブタスク: ワーカー割り当て済み かつ 依存関係がクリアされたタスク
        // これらは in_progress に変更可能
        let executableSubTasks = workerAssignedSubTasks.filter { task in
            // 依存タスクがない場合は実行可能
            if task.dependencies.isEmpty {
                return true
            }
            // 全ての依存タスクがdoneの場合のみ実行可能
            return task.dependencies.allSatisfy { depId in
                subTasks.first { $0.id == depId }?.status == .done
            }
        }

        Self.log("[MCP] getManagerNextAction: subTasks=\(subTasks.count), pending=\(pendingSubTasks.count), unassigned=\(unassignedSubTasks.count), workerAssigned=\(workerAssignedSubTasks.count), executable=\(executableSubTasks.count), inProgress=\(inProgressSubTasks.count), completed=\(completedSubTasks.count), blocked=\(blockedSubTasks.count)")

        // DEBUG: 各サブタスクの詳細をログ出力（バグ調査用）
        for task in subTasks {
            let depsStr = task.dependencies.map { $0.value }.joined(separator: ", ")
            let depsStatus = task.dependencies.map { depId -> String in
                if let depTask = subTasks.first(where: { $0.id == depId }) {
                    return "\(depId.value)=\(depTask.status.rawValue)"
                } else {
                    return "\(depId.value)=NOT_IN_SUBTASKS"
                }
            }.joined(separator: ", ")
            Self.log("[MCP] DEBUG subtask: id=\(task.id.value), status=\(task.status.rawValue), assignee=\(task.assigneeId?.value ?? "nil"), deps=[\(depsStr)], depsStatus=[\(depsStatus)]")
        }

        // サブタスクがまだ作成されていない
        if phase == "workflow:task_fetched" && subTasks.isEmpty {
            // サブタスク作成フェーズを記録
            // Note: Context.sessionId は sessions テーブルを参照するため、
            // 先に Session を作成してからその ID を使用する
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: mainTask.projectId,
                agentId: mainTask.assigneeId!,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)

            let context = Context(
                id: ContextID.generate(),
                taskId: mainTask.id,
                sessionId: workflowSession.id,
                agentId: mainTask.assigneeId!,
                progress: "workflow:creating_subtasks"
            )
            try contextRepository.save(context)

            return [
                "action": "create_subtasks",
                "instruction": """
                    タスクの複雑さを評価し、適切にサブタスクを作成してください（目安: 2〜5個）。
                    単純な場合は同一内容で1つ作成し即座に作業開始、
                    複雑な場合は明確な成果物単位で分解してください。
                    複数のサブタスクを作成する場合は create_tasks_batch ツールを使用してください。
                    parent_task_id には '\(mainTask.id.value)' を指定してください。
                    サブタスク作成後、get_next_action を呼び出してください。
                    """,
                "state": "needs_subtask_creation",
                "task": [
                    "id": mainTask.id.value,
                    "title": mainTask.title,
                    "description": mainTask.description
                ]
            ]
        }

        // サブタスクが存在する場合の処理
        if !subTasks.isEmpty {
            // 全サブタスクが完了 → completion_check（ただし selectedAction がある場合はスキップ）
            if completedSubTasks.count == subTasks.count {
                // selectedAction が既に選択されている場合は completion_check を返さず、
                // 下流の selectedAction 処理にフォールスルーする
                let latestCtx = try contextRepository.findLatest(taskId: mainTask.id)
                let hasSelectedAction = latestCtx?.progress?.hasPrefix("workflow:selected_") == true

                if !hasSelectedAction {
                    Self.log("[MCP] All subtasks completed, returning completion_check")
                    return [
                        "action": "completion_check",
                        "instruction": """
                            全てのサブタスクが完了しました。成果物を確認してください。

                            ■ 確認ツール
                            - list_tasks: サブタスクの完了状況を確認
                            - get_task: 各サブタスクの成果を確認
                            - delegate_to_chat_session: ワーカーに詳細を確認

                            ■ 次のアクション選択
                            確認後、select_action ツールで次のアクションを選択してください:
                            - complete: 完了処理に進む（report_completed を呼び出す）
                            - adjust: 調整が必要（修正や追加タスク作成）

                            選択後、get_next_action を呼び出してください。
                            """,
                        "state": "completion_check",
                        "task": [
                            "id": mainTask.id.value,
                            "title": mainTask.title
                        ],
                        "subtask_progress": [
                            "total": subTasks.count,
                            "done": completedSubTasks.count
                        ]
                    ]
                }
                Self.log("[MCP] All subtasks completed but selectedAction exists, falling through to action handling")
            }

            // 完了ゲート: blocked サブタスクがある場合の処理
            // 参照: docs/plan/BLOCKED_TASK_RECOVERY.md - Phase 1-5
            // 全サブタスクが完了済みまたはブロック状態で、未着手・進行中がない場合
            if !blockedSubTasks.isEmpty && pendingSubTasks.isEmpty && inProgressSubTasks.isEmpty {
                // ブロック種別ごとに分類
                var userBlockedTasks: [[String: Any]] = []
                var selfBlockedTasks: [[String: Any]] = []
                var otherBlockedTasks: [[String: Any]] = []

                for task in blockedSubTasks {
                    let taskInfo: [String: Any] = [
                        "id": task.id.value,
                        "title": task.title,
                        "blocked_reason": task.blockedReason ?? "理由未記載",
                        "blocked_by": task.statusChangedByAgentId?.value ?? "unknown"
                    ]

                    if let changedBy = task.statusChangedByAgentId {
                        if changedBy.isUserAction {
                            userBlockedTasks.append(taskInfo)
                        } else if changedBy == mainTask.assigneeId {
                            selfBlockedTasks.append(taskInfo)
                        } else {
                            // 下位ワーカーによるブロックも自己ブロック扱い
                            let subordinates = try agentRepository.findByParent(mainTask.assigneeId!)
                            if subordinates.contains(where: { $0.id == changedBy }) {
                                selfBlockedTasks.append(taskInfo)
                            } else {
                                otherBlockedTasks.append(taskInfo)
                            }
                        }
                    } else {
                        // nilは自己ブロック扱い（後方互換性）
                        selfBlockedTasks.append(taskInfo)
                    }
                }

                // 状態遷移: worker_blocked → handled_blocked
                // ブロック対処を返す際にコンテキストを更新して無限ループを防止
                let latestContext = try contextRepository.findLatest(taskId: mainTask.id)
                if latestContext?.progress == "workflow:worker_blocked" {
                    // worker_blocked から handled_blocked に遷移
                    // マネージャーが対処を試みた後、再起動されないようにする
                    let workflowSession = Session(
                        id: SessionID.generate(),
                        projectId: mainTask.projectId,
                        agentId: mainTask.assigneeId!,
                        startedAt: Date(),
                        status: .active
                    )
                    try sessionRepository.save(workflowSession)

                    let context = Context(
                        id: ContextID.generate(),
                        taskId: mainTask.id,
                        sessionId: workflowSession.id,
                        agentId: mainTask.assigneeId!,
                        progress: "workflow:handled_blocked",
                        blockers: "Handling blocked subtasks: \(blockedSubTasks.map { $0.id.value }.joined(separator: ", "))"
                    )
                    try contextRepository.save(context)
                    Self.log("[MCP] getManagerNextAction: Transitioned from worker_blocked to handled_blocked")
                }

                // Managerは全てのブロック状況を把握して対処を検討できる
                // 自己/下位ブロック → 解除可能、ユーザー/他者ブロック → 解除不可だが自主判断で対処
                return [
                    "action": "review_and_resolve_blocks",
                    "instruction": """
                        以下のサブタスクがブロック状態です。マネージャーとして自主的に対処を検討してください。

                        【ブロック種別と対応】
                        ■ 自己/下位ワーカーによるブロック（解除可能）:
                          - ブロック理由を確認してください
                          - 理由が解決済みなら update_task_status で 'todo' に変更
                          - assign_task でワーカーに再割り当て

                        ■ ユーザーによるブロック:
                          - ユーザーが意図的にブロックしたタスクです
                          - 直接解除する権限はありませんが、以下の対処を自主的に検討してください:
                            1. 別のワーカーへの再アサイン（assign_task）
                            2. タスクの分割・再設計（新しいサブタスクを作成）
                            3. 代替アプローチの検討
                            4. ブロック理由に基づく問題解決
                          - 対処不可能と判断した場合のみ、メインタスクをブロックとして報告

                        【最終判断】
                        - 自主的な対処を試みた上で、それでも完了できない場合:
                          → メインタスク自体を blocked にして report_completed で報告
                          → result は 'blocked'、summary に試みた対処と残る問題を記載
                        - すぐに諦めず、まず対処を試みてください
                        """,
                    "state": "needs_review",
                    "self_blocked_subtasks": selfBlockedTasks,
                    "user_blocked_subtasks": userBlockedTasks,
                    "other_blocked_subtasks": otherBlockedTasks,
                    "completed_subtasks": completedSubTasks.count,
                    "total_subtasks": subTasks.count,
                    "can_unblock_self": !selfBlockedTasks.isEmpty,
                    "has_unresolvable_blocks": !userBlockedTasks.isEmpty || !otherBlockedTasks.isEmpty
                ]
            }

            // ========================================
            // マネージャー状態遷移 V2
            // 参照: docs/design/MANAGER_STATE_MACHINE_V2.md
            // ========================================

            // 下位エージェント（Worker）を取得（複数箇所で使用）
            let subordinates = try agentRepository.findByParent(mainTask.assigneeId!)
                .filter { $0.hierarchyType == .worker && $0.status == .active }

            // 利用可能な Worker がいない場合、タスクを blocked 状態にする
            if subordinates.isEmpty && !unassignedSubTasks.isEmpty {
                Self.log("[MCP] No available workers, blocking subtask")
                let firstSubTask = unassignedSubTasks[0]
                return [
                    "action": "block_subtask",
                    "instruction": """
                        利用可能な Worker がいません。
                        update_task_status を使用して、サブタスク '\(firstSubTask.id.value)' のステータスを
                        'blocked' に変更し、blocked_reason に '利用可能なWorkerがいません' と設定してください。
                        その後、logout を呼び出してセッションを終了してください。
                        """,
                    "state": "no_available_workers",
                    "subtask_to_block": [
                        "id": firstSubTask.id.value,
                        "title": firstSubTask.title
                    ],
                    "reason": "no_available_workers",
                    "progress": [
                        "completed": completedSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            }

            // 選択されたアクションを確認
            let latestContext = try contextRepository.findLatest(taskId: mainTask.id)
            let selectedAction = latestContext?.progress.flatMap { progress -> String? in
                if progress.hasPrefix("workflow:selected_") {
                    return String(progress.dropFirst("workflow:selected_".count))
                }
                return nil
            }

            // サブタスク進捗情報（複数箇所で使用）
            let subtaskProgress: [String: Any] = [
                "total": subTasks.count,
                "todo": pendingSubTasks.count,
                "in_progress": inProgressSubTasks.count,
                "done": completedSubTasks.count,
                "blocked": blockedSubTasks.count,
                "unassigned": unassignedSubTasks.count,
                "executable": executableSubTasks.count
            ]

            // サブタスク個別リスト（situational_awareness で使用）
            let subtaskList: [[String: Any]] = subTasks.map { task in
                [
                    "id": task.id.value,
                    "title": task.title,
                    "status": task.status.rawValue,
                    "assignee_id": task.assigneeId?.value ?? "unassigned"
                ] as [String: Any]
            }

            // アクションが選択されている場合、対応する状態を返す
            if let action = selectedAction {
                Self.log("[MCP] Selected action found: \(action)")

                // 選択をクリア（次回は situational_awareness に戻る）
                let clearSession = Session(
                    id: SessionID.generate(),
                    projectId: mainTask.projectId,
                    agentId: mainTask.assigneeId!,
                    startedAt: Date(),
                    status: .active
                )
                try sessionRepository.save(clearSession)

                let clearContext = Context(
                    id: ContextID.generate(),
                    taskId: mainTask.id,
                    sessionId: clearSession.id,
                    agentId: mainTask.assigneeId!,
                    progress: "workflow:action_executed_\(action)"
                )
                try contextRepository.save(clearContext)

                switch action {
                case "dispatch_task":
                    // 派遣可能タスクを収集
                    var dispatchableSubTasks: [[String: Any]] = []
                    for task in unassignedSubTasks {
                        dispatchableSubTasks.append([
                            "id": task.id.value,
                            "title": task.title,
                            "description": task.description ?? "",
                            "assignee_id": NSNull(),
                            "status": "unassigned",
                            "deps_met": false
                        ])
                    }
                    for task in executableSubTasks {
                        dispatchableSubTasks.append([
                            "id": task.id.value,
                            "title": task.title,
                            "description": task.description ?? "",
                            "assignee_id": task.assigneeId?.value ?? NSNull(),
                            "status": "ready",
                            "deps_met": true
                        ])
                    }

                    Self.log("[MCP] dispatch_task: \(dispatchableSubTasks.count) tasks available")
                    return [
                        "action": "dispatch_task",
                        "instruction": """
                            タスクをワーカーに派遣してください。

                            ■ 派遣可能なタスク一覧
                            dispatchable_subtasks に派遣可能なタスクが含まれています。
                            - status: "unassigned" → 未割り当て（assign_task で割り当てが必要）
                            - status: "ready" → 割り当て済み（すぐに開始可能）

                            ■ 手順
                            1. 派遣するタスクを選択（優先度、Worker負荷を考慮して判断）
                            2. 未割り当ての場合: assign_task で割り当て
                            3. update_task_status で in_progress に変更

                            どのタスクを誰に割り当てるかはマネージャーの裁量で判断してください。
                            完了後、get_next_action を呼び出してください。
                            """,
                        "state": "dispatch_task",
                        "dispatchable_subtasks": dispatchableSubTasks,
                        "available_workers": subordinates.map { [
                            "id": $0.id.value,
                            "name": $0.name,
                            "role": $0.role,
                            "status": $0.status.rawValue
                        ] as [String: Any] },
                        "subtask_progress": subtaskProgress
                    ]

                case "adjust":
                    Self.log("[MCP] adjust: Returning adjust state")
                    return [
                        "action": "adjust",
                        "instruction": """
                            必要な調整を行ってください。

                            ■ 調整用ツール
                            - assign_task: 担当者変更・振り直し
                            - update_task_status: ステータス変更
                            - create_tasks_batch: 追加タスク作成
                            - split_task: 既存タスクを同階層の複数タスクに分割（元タスクはキャンセル、依存関係は引き継ぎ）

                            ■ ワーカーとのコミュニケーション
                            - delegate_to_chat_session: 下位ワーカーとチャットで対話
                              （状況確認、作業の調整指示など）

                            ■ 確認用ツール
                            - list_tasks: 全体状況確認
                            - get_task: 詳細確認
                            - list_subordinates: ワーカー状況確認
                            - get_subordinate_profile: ワーカーの詳細情報を確認

                            調整完了後、get_next_action を呼び出してください。
                            """,
                        "state": "adjust",
                        "available_workers": subordinates.map { [
                            "id": $0.id.value,
                            "name": $0.name,
                            "role": $0.role,
                            "status": $0.status.rawValue
                        ] as [String: Any] },
                        "subtask_progress": subtaskProgress
                    ]

                case "wait":
                    // 待機状態を Context に記録
                    let waitSession = Session(
                        id: SessionID.generate(),
                        projectId: mainTask.projectId,
                        agentId: mainTask.assigneeId!,
                        startedAt: Date(),
                        status: .active
                    )
                    try sessionRepository.save(waitSession)

                    let waitContext = Context(
                        id: ContextID.generate(),
                        taskId: mainTask.id,
                        sessionId: waitSession.id,
                        agentId: mainTask.assigneeId!,
                        progress: "workflow:waiting_for_workers"
                    )
                    try contextRepository.save(waitContext)

                    // セッション削除（再起動のためにhasTaskWork=trueになるようにする）
                    try agentSessionRepository.delete(session.id)
                    Self.log("[MCP] wait: AgentSession deleted for manager exit")

                    return [
                        "action": "wait",
                        "instruction": """
                            Worker の完了を待つため、プロセスを終了してください。
                            Coordinator が Worker 完了後に自動的に再起動します。
                            logout を呼び出してください。
                            """,
                        "state": "waiting_for_workers",
                        "in_progress_subtasks": inProgressSubTasks.map { [
                            "id": $0.id.value,
                            "title": $0.title,
                            "assignee_id": $0.assigneeId?.value ?? "unassigned"
                        ] as [String: Any] },
                        "subtask_progress": subtaskProgress
                    ]

                case "complete":
                    Self.log("[MCP] complete: Returning report_completion state")
                    return [
                        "action": "report_completion",
                        "instruction": """
                            完了チェックが完了しました。
                            report_completed を呼び出してメインタスクを完了してください。
                            result と summary は成果に応じて適切に設定してください。
                            """,
                        "state": "report_completion",
                        "task": [
                            "id": mainTask.id.value,
                            "title": mainTask.title
                        ],
                        "subtask_progress": subtaskProgress
                    ]

                default:
                    Self.log("[MCP] Unknown selected action: \(action), returning situational_awareness")
                }
            }

            // アクションが選択されていない場合: situational_awareness を返す
            // （派遣可能タスクがある、または実行中タスクがある場合）
            if !unassignedSubTasks.isEmpty || !executableSubTasks.isEmpty || !inProgressSubTasks.isEmpty {
                Self.log("[MCP] No action selected, returning situational_awareness")
                return [
                    "action": "situational_awareness",
                    "instruction": """
                        現在の状況を確認し、次のアクションを選択してください。

                        ■ 次のアクション選択
                        select_action ツールで次のアクションを選択してください:
                        - dispatch_task: タスクをワーカーに派遣する（割当+開始）
                        - adjust: 調整を行う（タスク修正、振り直し等）
                        - wait: ワーカーの作業完了を待つため一時退出する

                        選択後、get_next_action を呼び出してください。
                        """,
                    "state": "situational_awareness",
                    "my_task": [
                        "id": mainTask.id.value,
                        "title": mainTask.title,
                        "status": mainTask.status.rawValue
                    ] as [String: Any],
                    "subtasks": subtaskList,
                    "available_workers": subordinates.map { [
                        "id": $0.id.value,
                        "name": $0.name,
                        "role": $0.role,
                        "status": $0.status.rawValue
                    ] as [String: Any] }
                ]
            }

            // 全サブタスク完了でない場合は常に situational_awareness を返す
            // （マネージャーが select_action で wait を選択した場合のみ exit）
            Self.log("[MCP] No action selected, returning situational_awareness (fallback)")
            return [
                "action": "situational_awareness",
                "instruction": """
                    現在の状況を確認し、次のアクションを選択してください。

                    ■ 次のアクション選択
                    select_action ツールで次のアクションを選択してください:
                    - dispatch_task: タスクをワーカーに派遣する（割当+開始）
                    - adjust: 調整を行う（タスク修正、振り直し等）
                    - wait: ワーカーの作業完了を待つため一時退出する

                    選択後、get_next_action を呼び出してください。
                    """,
                "state": "situational_awareness",
                "main_task": [
                    "id": mainTask.id.value,
                    "title": mainTask.title
                ] as [String: Any],
                "subtasks": subtaskList,
                "available_workers": subordinates.map { [
                    "id": $0.id.value,
                    "name": $0.name,
                    "role": $0.role,
                    "status": $0.status.rawValue
                ] as [String: Any] }
            ]
        }

        // サブタスク作成中フェーズ
        if phase == "workflow:creating_subtasks" {
            // サブタスク作成完了を記録
            // Note: Context.sessionId は sessions テーブルを参照するため、
            // 先に Session を作成してからその ID を使用する
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: mainTask.projectId,
                agentId: mainTask.assigneeId!,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)

            let context = Context(
                id: ContextID.generate(),
                taskId: mainTask.id,
                sessionId: workflowSession.id,
                agentId: mainTask.assigneeId!,
                progress: "workflow:subtasks_created"
            )
            try contextRepository.save(context)

            // 下位エージェント（Worker）を取得
            let subordinates = try agentRepository.findByParent(mainTask.assigneeId!)
                .filter { $0.hierarchyType == .worker && $0.status == .active }

            // 利用可能な Worker がいない場合、タスクを blocked 状態にする
            if subordinates.isEmpty {
                Self.log("[MCP] No available workers after subtask creation, blocking subtasks")
                if let firstSubTask = unassignedSubTasks.first {
                    return [
                        "action": "block_subtask",
                        "instruction": """
                            利用可能な Worker がいません。
                            update_task_status を使用して、サブタスク '\(firstSubTask.id.value)' のステータスを
                            'blocked' に変更し、blocked_reason に '利用可能なWorkerがいません' と設定してください。
                            その後、logout を呼び出してセッションを終了してください。
                            """,
                        "state": "no_available_workers",
                        "subtask_to_block": [
                            "id": firstSubTask.id.value,
                            "title": firstSubTask.title
                        ],
                        "reason": "no_available_workers",
                        "subtasks": subTasks.map { [
                            "id": $0.id.value,
                            "title": $0.title
                        ] as [String: Any] }
                    ]
                }
            }

            // Phase 1: 未割り当てタスクをワーカーに割り当て（assignee変更のみ）
            if let nextSubTask = unassignedSubTasks.first {
                Self.log("[MCP] Assigning first task after subtask creation (unassigned: \(unassignedSubTasks.count))")
                return [
                    "action": "assign",
                    "instruction": """
                        サブタスクを Worker に割り当ててください。
                        assign_task ツールを使用して、task_id と assignee_id を指定してください。
                        【重要】この段階では in_progress に変更しないでください。割り当てのみ行います。
                        割り当て後、get_next_action を呼び出してください。
                        """,
                    "state": "needs_assignment",
                    "next_subtask": [
                        "id": nextSubTask.id.value,
                        "title": nextSubTask.title,
                        "description": nextSubTask.description
                    ],
                    "available_workers": subordinates.map { [
                        "id": $0.id.value,
                        "name": $0.name,
                        "role": $0.role,
                        "status": $0.status.rawValue
                    ] as [String: Any] },
                    "progress": [
                        "completed": completedSubTasks.count,
                        "unassigned": unassignedSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            }
        }

        // フォールバック
        return [
            "action": "get_task",
            "instruction": "get_my_task を呼び出してタスク詳細を取得してください。",
            "state": "needs_task"
        ]
    }


}
