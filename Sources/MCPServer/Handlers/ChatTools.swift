// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Chat Tools

extension MCPServer {

    // MARK: - Chat Tools
    // 参照: docs/design/CHAT_FEATURE.md

    /// get_pending_messages - 未読チャットメッセージを取得
    /// チャット目的で起動されたエージェントが呼び出す
    /// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 3
    ///
    /// 返り値:
    /// - context_messages: 文脈理解用の直近メッセージ（最大20件）
    /// - pending_messages: 応答対象の未読メッセージ（最大10件）
    /// - total_history_count: 全履歴の件数
    /// - context_truncated: コンテキストが切り詰められたかどうか
    func getPendingMessages(session: AgentSession) throws -> [String: Any] {
        Self.log("[MCP] getPendingMessages called: agentId='\(session.agentId.value)', projectId='\(session.projectId.value)'")

        // 全メッセージを取得
        let allMessages = try chatRepository.findMessages(
            projectId: session.projectId,
            agentId: session.agentId
        )

        Self.log("[MCP] Found \(allMessages.count) total message(s)")

        // 既読時刻を取得（既読時刻ベースの未読判定用）
        // Reference: docs/design/CHAT_FEATURE.md - Section 9.11
        let lastReadTimes = try chatRepository.getLastReadTimes(
            projectId: session.projectId,
            agentId: session.agentId
        )

        // PendingMessageIdentifier を使用してコンテキストと未読を分離
        // lastReadTimes を渡して既読時刻ベースの判定を有効化
        let rawResult = PendingMessageIdentifier.separateContextAndPending(
            allMessages,
            agentId: session.agentId,
            lastReadTimes: lastReadTimes,
            contextLimit: PendingMessageIdentifier.defaultContextLimit,  // 20
            pendingLimit: PendingMessageIdentifier.defaultPendingLimit   // 10
        )

        // 自動既読更新: フィルタ前に全送信者を既読にマーク（システムメッセージを含む）
        // これにより、システムメッセージも既読になり、不要なスポーンが防止される
        // Reference: docs/plan/UNREAD_MESSAGE_REFACTOR_TDD.md - Phase 3
        let allUniqueSenderIds = Set(rawResult.pendingMessages.map { $0.senderId })
        for senderId in allUniqueSenderIds {
            try chatRepository.markAsRead(
                projectId: session.projectId,
                currentAgentId: session.agentId,
                senderAgentId: senderId
            )
        }
        if !allUniqueSenderIds.isEmpty {
            Self.log("[MCP] Marked \(allUniqueSenderIds.count) sender(s) as read (including system)")
        }

        // Filter out system messages (senderId starts with "system")
        // These are used to trigger chat session spawn but should not be shown to agents
        // Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 2.2
        let filteredPending = rawResult.pendingMessages.filter { !$0.senderId.value.hasPrefix("system") }
        let filteredContext = rawResult.contextMessages.filter { !$0.senderId.value.hasPrefix("system") }

        let result = ContextAndPendingResult(
            contextMessages: filteredContext,
            pendingMessages: filteredPending,
            totalHistoryCount: rawResult.totalHistoryCount,
            contextTruncated: rawResult.contextTruncated
        )

        Self.log("[MCP] Context: \(result.contextMessages.count), Pending: \(result.pendingMessages.count), Truncated: \(result.contextTruncated)")

        // ISO8601フォーマッタを共有
        let formatter = ISO8601DateFormatter()

        // コンテキストメッセージを辞書に変換
        let contextDicts = result.contextMessages.map { message -> [String: Any] in
            var dict: [String: Any] = [
                "id": message.id.value,
                "sender_id": message.senderId.value,
                "content": message.content,
                "created_at": formatter.string(from: message.createdAt)
            ]
            if let receiverId = message.receiverId {
                dict["receiver_id"] = receiverId.value
            }
            return dict
        }

        // 未読メッセージを辞書に変換
        let pendingDicts = result.pendingMessages.map { message -> [String: Any] in
            var dict: [String: Any] = [
                "id": message.id.value,
                "sender_id": message.senderId.value,
                "content": message.content,
                "created_at": formatter.string(from: message.createdAt)
            ]
            if let receiverId = message.receiverId {
                dict["receiver_id"] = receiverId.value
            }
            return dict
        }

        // 指示文を生成
        let instruction: String
        if result.pendingMessages.isEmpty {
            instruction = "未読メッセージはありません。get_next_action を呼び出して次のアクションを確認してください。"
        } else {
            instruction = """
            上記の pending_messages を確認してください。
            context_messages は会話の文脈理解用です（応答対象ではありません）。

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
              → 作業依頼や通知・調整の意図がある場合:
                「以下のマーカーをつけてお送りください:
                 ・新規タスク作成: @@タスク作成: タイトル [--priority 優先度]
                 ・既存タスクへの通知: @@タスク通知: メッセージ [--task ID]
                 ・既存タスクの修正/削除: @@タスク調整: 内容 [--task ID]
                 ・タスクの実行開始: @@タスク開始: タスクID」と案内
              → 単なる質問や相談: send_message で直接応答

            【注意】タスク関連のコマンドを実行する前に、既存のタスク一覧・状況を確認し、
            新規作成・通知・調整・開始のどれが適切かを判断してください。
            重複タスクの作成や、存在しないタスクへの操作を防ぐためです。

            【例外】他のエージェントとの会話・対話を依頼された場合:
            - 「〜とチャットしてください」「〜と話し合ってください」など
            - この場合は start_conversation を使って直接会話を開始してください
            - 会話開始後、send_message でメッセージを交換してください
            """
        }

        return [
            "success": true,
            "context_messages": contextDicts,
            "pending_messages": pendingDicts,
            "total_history_count": result.totalHistoryCount,
            "context_truncated": result.contextTruncated,
            "instruction": instruction
        ]
    }

    /// send_message - プロジェクト内の他のエージェントにメッセージを送信
    /// タスクセッション・チャットセッションの両方で使用可能（.authenticated権限）
    /// 参照: docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md
    /// 参照: docs/design/AI_TO_AI_CONVERSATION.md - conversationId自動設定
    func sendMessage(
        session: AgentSession,
        targetAgentId: String,
        content: String,
        relatedTaskId: String?,
        conversationId: String? = nil
    ) throws -> [String: Any] {
        Self.log("[MCP] sendMessage called: from='\(session.agentId.value)' to='\(targetAgentId)' content_length=\(content.count)")

        // 1. コンテンツ長チェック（最大4,000文字）
        guard content.count <= 4000 else {
            throw MCPError.contentTooLong(maxLength: 4000, actual: content.count)
        }

        // 2. 自分自身への送信は禁止
        guard targetAgentId != session.agentId.value else {
            throw MCPError.cannotMessageSelf
        }

        // 3. 送信先エージェントの存在確認
        guard let targetAgent = try agentRepository.findById(AgentID(value: targetAgentId)) else {
            throw MCPError.agentNotFound(targetAgentId)
        }

        // 4. 同一プロジェクト内のエージェントか確認
        let isTargetInProject = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: AgentID(value: targetAgentId),
            projectId: session.projectId
        )
        guard isTargetInProject else {
            throw MCPError.targetAgentNotInProject(targetAgentId: targetAgentId, projectId: session.projectId.value)
        }

        // 5. conversationIdの解決
        // 明示的に指定されていない場合、アクティブまたはpending会話から自動設定
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md - pending状態でもイニシエーターからのメッセージは許可
        var resolvedConversationId: ConversationID? = nil
        if let convIdStr = conversationId {
            resolvedConversationId = ConversationID(value: convIdStr)
        } else {
            // 送信者と受信者間のアクティブな会話を検索
            let activeConversations = try conversationRepository.findActiveByAgentId(
                session.agentId,
                projectId: session.projectId
            )
            // 両者が参加している会話を探す
            if let activeConv = activeConversations.first(where: {
                $0.getPartnerId(for: session.agentId)?.value == targetAgentId
            }) {
                resolvedConversationId = activeConv.id
                Self.log("[MCP] Auto-resolved conversation_id from active: \(activeConv.id.value)")
            } else {
                // active会話がない場合、イニシエーターとしてpending会話を検索
                let pendingConversations = try conversationRepository.findPendingForInitiator(
                    session.agentId,
                    projectId: session.projectId
                )
                if let pendingConv = pendingConversations.first(where: {
                    $0.participantAgentId.value == targetAgentId
                }) {
                    resolvedConversationId = pendingConv.id
                    Self.log("[MCP] Auto-resolved conversation_id from pending (initiator): \(pendingConv.id.value)")
                }
            }
        }

        // 6. AI間メッセージ制約チェック
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md - send_message 制約
        // 両者がAIエージェントの場合、アクティブな会話が必須
        let senderAgent = try agentRepository.findById(session.agentId)
        if senderAgent?.type == .ai && targetAgent.type == .ai {
            guard resolvedConversationId != nil else {
                Self.log("[MCP] AI-to-AI message rejected: no active conversation between \(session.agentId.value) and \(targetAgentId)")
                throw MCPError.conversationRequiredForAIToAI(
                    fromAgentId: session.agentId.value,
                    toAgentId: targetAgentId
                )
            }
        }

        // 7. メッセージ作成
        let message = ChatMessage(
            id: ChatMessageID.generate(),
            senderId: session.agentId,
            receiverId: AgentID(value: targetAgentId),
            content: content,
            createdAt: Date(),
            relatedTaskId: relatedTaskId.map { TaskID(value: $0) },
            conversationId: resolvedConversationId
        )

        // 8. 双方向保存
        try chatRepository.saveMessageDualWrite(
            message,
            projectId: session.projectId,
            senderAgentId: session.agentId,
            receiverAgentId: AgentID(value: targetAgentId)
        )

        Self.log("[MCP] Message sent successfully: \(message.id.value) from \(session.agentId.value) to \(targetAgentId)")

        var result: [String: Any] = [
            "success": true,
            "message_id": message.id.value,
            "target_agent_id": targetAgentId
        ]
        if let convId = resolvedConversationId {
            result["conversation_id"] = convId.value

            // 会話内メッセージ数をカウント
            // 参照: docs/design/AI_TO_AI_CONVERSATION.md
            let allMessages = try chatRepository.findMessages(projectId: session.projectId, agentId: session.agentId)
            let conversationMessageCount = allMessages.filter { $0.conversationId == convId }.count

            // 会話を取得してmax_turnsをチェック
            if let conversation = try conversationRepository.findById(convId) {
                result["current_turns"] = conversationMessageCount
                result["max_turns"] = conversation.maxTurns

                // ターン数上限に達した場合、会話を自動終了
                if conversationMessageCount >= conversation.maxTurns {
                    try conversationRepository.updateState(convId, state: .ended, endedAt: Date())
                    result["conversation_ended"] = true
                    result["warning"] = "【会話終了】最大ターン数（\(conversation.maxTurns)）に達したため会話を自動終了しました。必要であれば新しい会話を開始してください。"
                    Self.log("[MCP] sendMessage: Conversation auto-ended due to max_turns limit: \(conversationMessageCount)/\(conversation.maxTurns)")
                } else if conversationMessageCount > 0 && conversationMessageCount % 5 == 0 {
                    // 5件ごとにリマインド
                    result["reminder"] = "【確認】会話の目的は達成されましたか？達成された場合は end_conversation で会話を終了してください。（\(conversationMessageCount)/\(conversation.maxTurns)ターン）"
                    Self.log("[MCP] sendMessage: Conversation reminder added at message count: \(conversationMessageCount)/\(conversation.maxTurns)")
                }
            }
        }

        // セッションの lastActivityAt を更新（タイムアウト管理のため）
        // 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md
        try agentSessionRepository.updateLastActivity(token: session.token)

        return result
    }


}
