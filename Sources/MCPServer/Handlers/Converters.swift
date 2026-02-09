// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Entity Converters

extension MCPServer {

    // MARK: - Helper Methods

    func agentToDict(_ agent: Agent) -> [String: Any] {
        var dict: [String: Any] = [
            "id": agent.id.value,
            "name": agent.name,
            "role": agent.role,
            "type": agent.type.rawValue,
            "role_type": agent.roleType.rawValue,
            "capabilities": agent.capabilities,
            "status": agent.status.rawValue,
            "created_at": ISO8601DateFormatter().string(from: agent.createdAt)
        ]

        // AIタイプがあれば追加
        if let aiType = agent.aiType {
            dict["ai_type"] = aiType.rawValue
        }

        return dict
    }

    func projectToDict(_ project: Project) -> [String: Any] {
        // Note: working_directoryはコーディネーターが管理するため返さない
        return [
            "id": project.id.value,
            "name": project.name,
            "description": project.description,
            "status": project.status.rawValue,
            "created_at": ISO8601DateFormatter().string(from: project.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: project.updatedAt)
        ]
    }

    func taskToDict(_ task: Task) -> [String: Any] {
        var dict: [String: Any] = [
            "id": task.id.value,
            "project_id": task.projectId.value,
            "title": task.title,
            "description": task.description,
            "status": task.status.rawValue,
            "priority": task.priority.rawValue,
            "created_at": ISO8601DateFormatter().string(from: task.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: task.updatedAt)
        ]

        if let assigneeId = task.assigneeId {
            dict["assignee_id"] = assigneeId.value
        }
        if let estimatedMinutes = task.estimatedMinutes {
            dict["estimated_minutes"] = estimatedMinutes
        }
        if let actualMinutes = task.actualMinutes {
            dict["actual_minutes"] = actualMinutes
        }
        if let completedAt = task.completedAt {
            dict["completed_at"] = ISO8601DateFormatter().string(from: completedAt)
        }
        if let completionResult = task.completionResult {
            dict["completion_result"] = completionResult
        }
        if let completionSummary = task.completionSummary {
            dict["completion_summary"] = completionSummary
        }

        return dict
    }

    func sessionToDict(_ session: Session) -> [String: Any] {
        var dict: [String: Any] = [
            "id": session.id.value,
            "project_id": session.projectId.value,
            "agent_id": session.agentId.value,
            "status": session.status.rawValue,
            "started_at": ISO8601DateFormatter().string(from: session.startedAt)
        ]

        if let endedAt = session.endedAt {
            dict["ended_at"] = ISO8601DateFormatter().string(from: endedAt)
        }

        return dict
    }

    func contextToDict(_ context: Context) -> [String: Any] {
        var dict: [String: Any] = [
            "id": context.id.value,
            "task_id": context.taskId.value,
            "session_id": context.sessionId.value,
            "agent_id": context.agentId.value,
            "created_at": ISO8601DateFormatter().string(from: context.createdAt)
        ]

        if let progress = context.progress {
            dict["progress"] = progress
        }
        if let findings = context.findings {
            dict["findings"] = findings
        }
        if let blockers = context.blockers {
            dict["blockers"] = blockers
        }
        if let nextSteps = context.nextSteps {
            dict["next_steps"] = nextSteps
        }

        return dict
    }

    func handoffToDict(_ handoff: Handoff) -> [String: Any] {
        var dict: [String: Any] = [
            "id": handoff.id.value,
            "task_id": handoff.taskId.value,
            "from_agent_id": handoff.fromAgentId.value,
            "summary": handoff.summary,
            "created_at": ISO8601DateFormatter().string(from: handoff.createdAt)
        ]

        if let toAgentId = handoff.toAgentId {
            dict["to_agent_id"] = toAgentId.value
        }
        if let context = handoff.context {
            dict["context"] = context
        }
        if let recommendations = handoff.recommendations {
            dict["recommendations"] = recommendations
        }
        if let acceptedAt = handoff.acceptedAt {
            dict["accepted_at"] = ISO8601DateFormatter().string(from: acceptedAt)
        }

        return dict
    }

    func eventToDict(_ event: StateChangeEvent) -> [String: Any] {
        var dict: [String: Any] = [
            "id": event.id.value,
            "project_id": event.projectId.value,
            "entity_type": event.entityType.rawValue,
            "entity_id": event.entityId,
            "event_type": event.eventType.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: event.timestamp)
        ]

        if let agentId = event.agentId {
            dict["agent_id"] = agentId.value
        }
        if let sessionId = event.sessionId {
            dict["session_id"] = sessionId.value
        }
        if let previousState = event.previousState {
            dict["previous_state"] = previousState
        }
        if let newState = event.newState {
            dict["new_state"] = newState
        }
        if let reason = event.reason {
            dict["reason"] = reason
        }
        if let metadata = event.metadata {
            dict["metadata"] = metadata
        }

        return dict
    }


}
