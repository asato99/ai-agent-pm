// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Chat-Task Operations & Session Notification

extension MCPServer {

    // MARK: - Chat → Task Operation Tools
    // 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 3

    /// start_task_from_chat - チャットセッションから既存タスクの実行を開始
    /// 上位者（祖先エージェント）からの依頼がある場合のみ許可される
    func startTaskFromChat(session: AgentSession, taskId: String, requesterId: String) throws -> [String: Any] {
        Self.log("[MCP] startTaskFromChat called: agentId='\(session.agentId.value)', taskId='\(taskId)', requesterId='\(requesterId)'")

        // タスクの存在確認
        guard let task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        // 割り当て確認 - 自分に割り当てられているか
        guard task.assigneeId == session.agentId else {
            throw MCPError.taskAccessDenied(taskId)
        }

        // 依頼者が上位者（祖先エージェント）であることを確認
        let requesterAgentId = AgentID(value: requesterId)
        let isAncestor = try isAncestorAgent(ancestorId: requesterAgentId, descendantId: session.agentId)
        guard isAncestor else {
            throw MCPError.permissionDenied("依頼者(\(requesterId))が上位者ではありません。チャットからのタスク操作は上位者からの依頼がある場合のみ許可されます。")
        }

        // 依頼者がプロジェクトに所属していることを確認
        let isRequesterInProject = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: requesterAgentId,
            projectId: session.projectId
        )
        guard isRequesterInProject else {
            throw MCPError.agentNotAssignedToProject(agentId: requesterId, projectId: session.projectId.value)
        }

        // タスクステータスを in_progress に変更
        var updatedTask = task
        updatedTask.status = .inProgress
        updatedTask.updatedAt = Date()
        try taskRepository.save(updatedTask)

        Self.log("[MCP] startTaskFromChat completed: taskId='\(taskId)', new_status='in_progress'")

        return [
            "success": true,
            "task_id": taskId,
            "new_status": "in_progress",
            "instruction": "タスクの実行を開始しました。タスクセッションへ切り替えて実行を継続してください。"
        ]
    }

    /// update_task_from_chat - チャットセッションからタスクを修正
    /// 上位者（祖先エージェント）からの依頼がある場合のみ許可される
    func updateTaskFromChat(session: AgentSession, taskId: String, requesterId: String, description: String?, status: String?) throws -> [String: Any] {
        Self.log("[MCP] updateTaskFromChat called: agentId='\(session.agentId.value)', taskId='\(taskId)', requesterId='\(requesterId)'")

        // タスクの存在確認
        guard let task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        // 割り当て確認 - 自分に割り当てられているか
        guard task.assigneeId == session.agentId else {
            throw MCPError.taskAccessDenied(taskId)
        }

        // 依頼者が上位者（祖先エージェント）であることを確認
        let requesterAgentId = AgentID(value: requesterId)
        let isAncestor = try isAncestorAgent(ancestorId: requesterAgentId, descendantId: session.agentId)
        guard isAncestor else {
            throw MCPError.permissionDenied("依頼者(\(requesterId))が上位者ではありません。チャットからのタスク操作は上位者からの依頼がある場合のみ許可されます。")
        }

        // 依頼者がプロジェクトに所属していることを確認
        let isRequesterInProject = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: requesterAgentId,
            projectId: session.projectId
        )
        guard isRequesterInProject else {
            throw MCPError.agentNotAssignedToProject(agentId: requesterId, projectId: session.projectId.value)
        }

        // タスクを更新
        var updatedTask = task
        var changes: [String] = []

        if let newDescription = description {
            updatedTask.description = newDescription
            changes.append("description")
        }

        if let newStatus = status {
            guard let taskStatus = TaskStatus(rawValue: newStatus) else {
                throw MCPError.invalidStatus(newStatus)
            }
            updatedTask.status = taskStatus
            changes.append("status")
        }

        updatedTask.updatedAt = Date()
        try taskRepository.save(updatedTask)

        Self.log("[MCP] updateTaskFromChat completed: taskId='\(taskId)', changes=\(changes)")

        return [
            "success": true,
            "task_id": taskId,
            "updated_fields": changes,
            "instruction": "タスクを更新しました。"
        ]
    }

    /// エージェントが別のエージェントの祖先（上位者）かどうかを確認
    /// ancestorIdがdescendantIdの祖先（parent, grandparent, etc.）であればtrue
    func isAncestorAgent(ancestorId: AgentID, descendantId: AgentID) throws -> Bool {
        var currentId: AgentID? = descendantId

        while let id = currentId {
            guard let agent = try agentRepository.findById(id) else {
                return false
            }

            if let parentId = agent.parentAgentId {
                if parentId == ancestorId {
                    return true
                }
                currentId = parentId
            } else {
                // ルートに到達、祖先なし
                return false
            }
        }

        return false
    }

    // MARK: - Session Notification Tools
    // 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 4

    /// notify_task_session - チャットセッションからタスクセッションへ通知を送信
    /// 同一エージェントの別セッションへ通知を送る（自分自身への通知）
    func notifyTaskSession(
        session: AgentSession,
        message: String,
        conversationId: String?,
        relatedTaskId: String?,
        priority: String?
    ) throws -> [String: Any] {
        Self.log("[MCP] notifyTaskSession called: agentId='\(session.agentId.value)', message_length=\(message.count)")

        // 会話IDが指定されている場合は存在確認
        var convId: ConversationID?
        if let conversationIdStr = conversationId {
            convId = ConversationID(value: conversationIdStr)
            // 会話の存在と参加確認
            guard let conversation = try conversationRepository.findById(convId!) else {
                throw MCPError.conversationNotFound(conversationIdStr)
            }
            guard conversation.isParticipant(session.agentId) else {
                throw MCPError.permissionDenied("You are not a participant of this conversation")
            }
        }

        // 関連タスクID
        let taskId: TaskID? = relatedTaskId.map { TaskID(value: $0) }

        // 優先度のバリデーション（現在は情報として保存、将来の拡張用）
        let validPriorities = ["normal", "high", "urgent"]
        let normalizedPriority = priority ?? "normal"
        if !validPriorities.contains(normalizedPriority) {
            throw MCPError.validationError("priority must be one of: normal, high, urgent")
        }

        // チャットセッション通知を作成
        // convIdがnilの場合は、ダミーのConversationIDを生成（メッセージのみの通知）
        let notificationConvId = convId ?? ConversationID.generate()
        let notification = AgentNotification.createChatSessionNotification(
            targetAgentId: session.agentId,
            targetProjectId: session.projectId,
            conversationId: notificationConvId,
            message: message,
            relatedTaskId: taskId
        )

        // 通知を保存
        try notificationRepository.save(notification)

        Self.log("[MCP] notifyTaskSession completed: notificationId='\(notification.id.value)'")

        return [
            "success": true,
            "notification_id": notification.id.value,
            "instruction": """
                通知を送信しました。タスクセッションは get_notifications で通知を取得し、
                get_conversation_messages で会話内容を確認できます。
                """
        ]
    }

    /// get_conversation_messages - 会話IDでメッセージを取得
    /// タスクセッションがチャットセッションからの通知を確認するために使用
    func getConversationMessages(
        session: AgentSession,
        conversationId: String,
        limit: Int?
    ) throws -> [String: Any] {
        Self.log("[MCP] getConversationMessages called: agentId='\(session.agentId.value)', conversationId='\(conversationId)'")

        let convId = ConversationID(value: conversationId)

        // 会話の存在と参加確認
        guard let conversation = try conversationRepository.findById(convId) else {
            throw MCPError.conversationNotFound(conversationId)
        }
        guard conversation.isParticipant(session.agentId) else {
            throw MCPError.permissionDenied("You are not a participant of this conversation")
        }

        // メッセージを取得
        let messages = try chatRepository.findByConversationId(
            projectId: session.projectId,
            agentId: session.agentId,
            conversationId: convId
        )

        // limit適用
        let effectiveLimit = min(limit ?? 50, 100)
        let limitedMessages = messages.suffix(effectiveLimit)

        // レスポンス形式に変換
        let formattedMessages = limitedMessages.map { msg -> [String: Any] in
            var result: [String: Any] = [
                "id": msg.id.value,
                "sender_id": msg.senderId.value,
                "content": msg.content,
                "created_at": ISO8601DateFormatter().string(from: msg.createdAt)
            ]
            if let receiverId = msg.receiverId {
                result["receiver_id"] = receiverId.value
            }
            if let taskId = msg.relatedTaskId {
                result["related_task_id"] = taskId.value
            }
            return result
        }

        Self.log("[MCP] getConversationMessages completed: found \(messages.count) messages, returning \(formattedMessages.count)")

        return [
            "conversation_id": conversationId,
            "conversation_state": conversation.state.rawValue,
            "initiator_agent_id": conversation.initiatorAgentId.value,
            "participant_agent_id": conversation.participantAgentId.value,
            "messages": Array(formattedMessages),
            "total_count": messages.count,
            "truncated": messages.count > effectiveLimit
        ]
    }


}
