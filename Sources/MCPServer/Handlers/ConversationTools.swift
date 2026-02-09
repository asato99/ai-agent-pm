// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - AI-to-AI Conversation & Chat Delegation

extension MCPServer {

    // MARK: - AI-to-AI Conversation Tools
    // 参照: docs/design/AI_TO_AI_CONVERSATION.md

    /// start_conversation - 他のAIエージェントとの会話を開始
    func startConversation(
        session: AgentSession,
        participantAgentId: String,
        purpose: String?,
        initialMessage: String,
        maxTurns: Int
    ) throws -> [String: Any] {
        Self.log("[MCP] startConversation called: initiator='\(session.agentId.value)' participant='\(participantAgentId)' maxTurns=\(maxTurns)")

        // 1. コンテンツ長チェック
        guard initialMessage.count <= 4000 else {
            throw MCPError.contentTooLong(maxLength: 4000, actual: initialMessage.count)
        }

        // 2. 自分自身との会話は禁止
        guard participantAgentId != session.agentId.value else {
            throw MCPError.cannotMessageSelf
        }

        // 3. 参加者エージェントの存在確認
        guard let _ = try agentRepository.findById(AgentID(value: participantAgentId)) else {
            throw MCPError.agentNotFound(participantAgentId)
        }

        // 4. 同一プロジェクト内のエージェントか確認
        let isParticipantInProject = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: AgentID(value: participantAgentId),
            projectId: session.projectId
        )
        guard isParticipantInProject else {
            throw MCPError.targetAgentNotInProject(targetAgentId: participantAgentId, projectId: session.projectId.value)
        }

        // 5. 既存のアクティブ/保留中会話がないか確認（重複防止）
        let hasExisting = try conversationRepository.hasActiveOrPendingConversation(
            initiatorAgentId: session.agentId,
            participantAgentId: AgentID(value: participantAgentId),
            projectId: session.projectId
        )
        if hasExisting {
            throw MCPError.conversationAlreadyExists(
                initiator: session.agentId.value,
                participant: participantAgentId
            )
        }

        // 6. ChatDelegationからtaskIdを継承（存在する場合）
        // 参照: docs/design/TASK_CONVERSATION_AWAIT.md - 会話へのtaskId紐付け
        var inheritedTaskId: TaskID? = nil
        if session.purpose == .chat {
            // チャットセッションからの会話開始時、処理中の委譲があればtaskIdを継承
            // 委譲は同じエージェントのタスクセッションから作成され、getNextActionでprocessingに更新済み
            if let processingDelegation = try chatDelegationRepository.findProcessingDelegation(
                agentId: session.agentId,
                targetAgentId: AgentID(value: participantAgentId),
                projectId: session.projectId
            ) {
                inheritedTaskId = processingDelegation.taskId
                Self.log("[MCP] startConversation: Inherited taskId from delegation: \(processingDelegation.taskId?.value ?? "nil")")
            }
        }

        // 7. 会話エンティティ作成
        // maxTurnsはシステム上限（40）以下に制限
        let validatedMaxTurns = min(max(maxTurns, 2), Conversation.systemMaxTurns)
        let conversation = Conversation(
            id: ConversationID.generate(),
            projectId: session.projectId,
            taskId: inheritedTaskId,
            initiatorAgentId: session.agentId,
            participantAgentId: AgentID(value: participantAgentId),
            state: .pending,
            purpose: purpose,
            maxTurns: validatedMaxTurns,
            createdAt: Date()
        )
        try conversationRepository.save(conversation)
        Self.log("[MCP] Created conversation: \(conversation.id.value) state=pending maxTurns=\(validatedMaxTurns) taskId=\(inheritedTaskId?.value ?? "nil")")

        // 7. 初期メッセージを送信（会話IDを紐付け）
        let message = ChatMessage(
            id: ChatMessageID.generate(),
            senderId: session.agentId,
            receiverId: AgentID(value: participantAgentId),
            content: initialMessage,
            createdAt: Date(),
            conversationId: conversation.id
        )
        try chatRepository.saveMessageDualWrite(
            message,
            projectId: session.projectId,
            senderAgentId: session.agentId,
            receiverAgentId: AgentID(value: participantAgentId)
        )

        return [
            "success": true,
            "conversation_id": conversation.id.value,
            "state": conversation.state.rawValue,
            "participant_agent_id": participantAgentId,
            "message_id": message.id.value,
            "instruction": "会話を開始しました。相手エージェントが認証後、会話がアクティブになります。send_messageでメッセージを送信し、get_next_actionで相手の応答を待機してください。"
        ]
    }

    /// end_conversation - AI-to-AI会話を終了
    func endConversation(
        session: AgentSession,
        conversationId: String,
        finalMessage: String?
    ) throws -> [String: Any] {
        Self.log("[MCP] endConversation called: conversation='\(conversationId)' by='\(session.agentId.value)'")

        // 1. 会話の存在確認
        let convId = ConversationID(value: conversationId)
        guard let conversation = try conversationRepository.findById(convId) else {
            throw MCPError.conversationNotFound(conversationId)
        }

        // 2. 参加者確認
        guard conversation.isParticipant(session.agentId) else {
            throw MCPError.notConversationParticipant(
                conversationId: conversationId,
                agentId: session.agentId.value
            )
        }

        // 3. 会話状態の確認
        guard conversation.state == .active || conversation.state == .pending else {
            throw MCPError.conversationNotActive(
                conversationId: conversationId,
                currentState: conversation.state.rawValue
            )
        }

        // 4. 最終メッセージがあれば送信
        if let finalMsg = finalMessage, !finalMsg.isEmpty {
            guard finalMsg.count <= 4000 else {
                throw MCPError.contentTooLong(maxLength: 4000, actual: finalMsg.count)
            }

            let partnerId = conversation.getPartnerId(for: session.agentId)!
            let message = ChatMessage(
                id: ChatMessageID.generate(),
                senderId: session.agentId,
                receiverId: partnerId,
                content: finalMsg,
                createdAt: Date(),
                conversationId: convId
            )
            try chatRepository.saveMessageDualWrite(
                message,
                projectId: session.projectId,
                senderAgentId: session.agentId,
                receiverAgentId: partnerId
            )
            Self.log("[MCP] Sent final message: \(message.id.value)")
        }

        // 5. 会話状態を terminating に更新
        try conversationRepository.updateState(convId, state: .terminating)
        Self.log("[MCP] Conversation state updated to terminating: \(conversationId)")

        return [
            "success": true,
            "conversation_id": conversationId,
            "state": ConversationState.terminating.rawValue,
            "instruction": "会話終了を要求しました。相手エージェントが終了を確認後、会話は完全に終了します。"
        ]
    }

    // MARK: - Chat Delegation

    /// delegate_to_chat_session - タスクセッションからチャットセッションへ委譲
    /// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
    func delegateToChatSession(
        session: AgentSession,
        targetAgentId: String,
        purpose: String,
        context: String?
    ) throws -> [String: Any] {
        Self.log("[MCP] delegateToChatSession called: agent='\(session.agentId.value)' target='\(targetAgentId)' purpose='\(purpose)'")

        // 1. タスクセッションからのみ呼び出し可能
        guard session.purpose == .task else {
            throw MCPError.toolNotAvailable(
                tool: "delegate_to_chat_session",
                reason: "このツールはタスクセッション専用です。現在のセッション目的: \(session.purpose.rawValue)"
            )
        }

        // 2. ターゲットエージェントの存在確認と情報取得
        // 参照: docs/design/TASK_CONVERSATION_AWAIT.md - instruction生成のためにエージェントタイプを取得
        let targetId = AgentID(value: targetAgentId)
        guard let targetAgent = try agentRepository.findById(targetId) else {
            throw MCPError.agentNotFound(targetAgentId)
        }

        // 3. ターゲットエージェントが同じプロジェクトに所属しているか確認
        let projectAgents = try projectAgentAssignmentRepository.findAgentsByProject(session.projectId)
        guard projectAgents.contains(where: { $0.id.value == targetAgentId }) else {
            throw MCPError.agentNotAssignedToProject(
                agentId: targetAgentId,
                projectId: session.projectId.value
            )
        }

        // 4. 自分自身への委譲は不可
        guard targetAgentId != session.agentId.value else {
            throw MCPError.invalidOperation("自分自身にチャットを委譲することはできません")
        }

        // 5. ChatDelegationを作成して保存
        // 参照: docs/design/TASK_CONVERSATION_AWAIT.md - session.taskIdを継承
        let delegation = ChatDelegation(
            id: ChatDelegationID.generate(),
            agentId: session.agentId,
            projectId: session.projectId,
            taskId: session.taskId,
            targetAgentId: targetId,
            purpose: purpose,
            context: context,
            status: .pending,
            createdAt: Date(),
            processedAt: nil,
            result: nil
        )
        try chatDelegationRepository.save(delegation)

        Self.log("[MCP] ChatDelegation created: \(delegation.id.value) taskId=\(session.taskId?.value ?? "nil")")

        // 6. 動的instructionの生成
        // 参照: docs/design/TASK_CONVERSATION_AWAIT.md - エージェントタイプに応じた指示
        let targetTypeNote = targetAgent.type == .ai
            ? "相手はAIのため、人間より応答が速い傾向があります。"
            : "相手は人間のため、応答に時間がかかる可能性があります。"

        let instruction = """
            会話を \(targetAgent.name)（\(targetAgent.type == .ai ? "AI" : "人間")）に移譲しました。確認方法：get_task_conversations()

            【確認頻度】
            タスク内に他の作業があれば、作業を進めつつ区切りで確認してください。
            他の作業がなければ、確認の頻度を上げてください。
            \(targetTypeNote)

            【中断判断】
            相手のタイプ、会話の進捗状況、応答の見込みを考慮して判断してください。
            見込みがないと判断したら、タスクを blocked に変更し理由を記録して退出。
            """

        return [
            "success": true,
            "target_agent_id": targetAgentId,
            "purpose": purpose,
            "instruction": instruction
        ]
    }

    /// get_task_conversations - タスクに紐付く会話を取得
    /// タスクセッションから委譲した会話の状況を確認するために使用
    /// 参照: docs/design/TASK_CONVERSATION_AWAIT.md
    func getTaskConversations(session: AgentSession) throws -> [String: Any] {
        Self.log("[MCP] getTaskConversations called: agent='\(session.agentId.value)' taskId=\(session.taskId?.value ?? "nil")")

        // 1. タスクセッションからのみ呼び出し可能
        guard session.purpose == .task else {
            throw MCPError.toolNotAvailable(
                tool: "get_task_conversations",
                reason: "このツールはタスクセッション専用です。現在のセッション目的: \(session.purpose.rawValue)"
            )
        }

        // 2. taskIdが必要
        guard let taskId = session.taskId else {
            return [
                "success": true,
                "conversations": [] as [[String: Any]],
                "instruction": "このタスクセッションには紐付くタスクがありません。"
            ]
        }

        // 3. 会話を検索（現在のタスク + 親タスクも含める）
        // サブタスクのセッションでも親タスクの会話を確認できるようにする
        var conversations = try conversationRepository.findByTaskId(taskId, projectId: session.projectId)
        var searchedTaskIds = [taskId.value]

        // 親タスクがあれば、その会話も検索
        if let task = try taskRepository.findById(taskId),
           let parentTaskId = task.parentTaskId {
            let parentConversations = try conversationRepository.findByTaskId(parentTaskId, projectId: session.projectId)
            // 重複を避けて追加
            let existingIds = Set(conversations.map { $0.id.value })
            for conv in parentConversations where !existingIds.contains(conv.id.value) {
                conversations.append(conv)
            }
            searchedTaskIds.append(parentTaskId.value)
            Self.log("[MCP] getTaskConversations: Also searched parent task \(parentTaskId.value)")
        }

        // 4. 会話情報を整形
        let conversationDicts: [[String: Any]] = conversations.map { conv in
            [
                "conversation_id": conv.id.value,
                "state": conv.state.rawValue,
                "initiator_agent_id": conv.initiatorAgentId.value,
                "participant_agent_id": conv.participantAgentId.value,
                "purpose": conv.purpose ?? "",
                "created_at": ISO8601DateFormatter().string(from: conv.createdAt),
                "ended_at": conv.endedAt.map { ISO8601DateFormatter().string(from: $0) } as Any
            ]
        }

        // 5. 状態別のサマリー
        let activeCount = conversations.filter { $0.state == .active }.count
        let pendingCount = conversations.filter { $0.state == .pending }.count
        let endedCount = conversations.filter { $0.state == .ended || $0.state == .expired }.count
        let terminatingCount = conversations.filter { $0.state == .terminating }.count

        let instruction: String
        if conversations.isEmpty {
            instruction = "このタスクに紐付く会話はまだありません。"
        } else if activeCount > 0 || pendingCount > 0 {
            instruction = """
                進行中の会話があります。
                - active: \(activeCount)件（両者参加中）
                - pending: \(pendingCount)件（相手の参加待ち）
                - terminating: \(terminatingCount)件（終了処理中）
                - ended: \(endedCount)件（終了済み）

                会話の応答を待つか、他の作業を進めてください。
                """
        } else {
            instruction = """
                すべての会話が終了しています。
                - ended: \(endedCount)件（終了済み）

                必要に応じて結果を確認してタスクを進めてください。
                """
        }

        Self.log("[MCP] getTaskConversations: Found \(conversations.count) conversations (active=\(activeCount), pending=\(pendingCount), ended=\(endedCount))")

        return [
            "success": true,
            "task_id": taskId.value,
            "conversations": conversationDicts,
            "summary": [
                "total": conversations.count,
                "active": activeCount,
                "pending": pendingCount,
                "terminating": terminatingCount,
                "ended": endedCount
            ],
            "instruction": instruction
        ]
    }

    /// report_delegation_completed - 委譲処理の完了報告
    /// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
    func reportDelegationCompleted(
        session: AgentSession,
        delegationId: String,
        result: String?
    ) throws -> [String: Any] {
        Self.log("[MCP] reportDelegationCompleted called: delegation='\(delegationId)' by='\(session.agentId.value)'")

        // 1. チャットセッションからのみ呼び出し可能
        guard session.purpose == .chat else {
            throw MCPError.toolNotAvailable(
                tool: "report_delegation_completed",
                reason: "このツールはチャットセッション専用です。現在のセッション目的: \(session.purpose.rawValue)"
            )
        }

        // 2. 委譲の存在確認
        let delId = ChatDelegationID(value: delegationId)
        guard let delegation = try chatDelegationRepository.findById(delId) else {
            throw MCPError.delegationNotFound(delegationId)
        }

        // 3. 自分の委譲であることを確認
        guard delegation.agentId == session.agentId else {
            throw MCPError.notDelegationOwner(
                delegationId: delegationId,
                agentId: session.agentId.value
            )
        }

        // 4. 委譲状態の確認（pending or processing のみ完了可能）
        guard delegation.status == .pending || delegation.status == .processing else {
            throw MCPError.delegationAlreadyProcessed(
                delegationId: delegationId,
                currentStatus: delegation.status.rawValue
            )
        }

        // 5. 完了マーク
        try chatDelegationRepository.markCompleted(delId, result: result)

        Self.log("[MCP] ChatDelegation completed: \(delegationId)")

        return [
            "success": true,
            "delegation_id": delegationId,
            "status": "completed",
            "instruction": "委譲処理の完了を報告しました。"
        ]
    }


}
