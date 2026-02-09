// Tests/UseCaseTests/MockRepositories.swift
// Shared mock repository implementations for UseCase tests
// Extracted from UseCaseTests.swift

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Mock Repositories

final class MockProjectRepository: ProjectRepositoryProtocol {
    var projects: [ProjectID: Project] = [:]

    func findById(_ id: ProjectID) throws -> Project? {
        projects[id]
    }

    func findAll() throws -> [Project] {
        Array(projects.values)
    }

    func save(_ project: Project) throws {
        projects[project.id] = project
    }

    func delete(_ id: ProjectID) throws {
        projects.removeValue(forKey: id)
    }
}

final class MockAgentRepository: AgentRepositoryProtocol {
    var agents: [AgentID: Agent] = [:]

    func findById(_ id: AgentID) throws -> Agent? {
        agents[id]
    }

    func findAll() throws -> [Agent] {
        Array(agents.values)
    }

    func findByType(_ type: AgentType) throws -> [Agent] {
        agents.values.filter { $0.type == type }
    }

    func findByParent(_ parentAgentId: AgentID?) throws -> [Agent] {
        agents.values.filter { $0.parentAgentId == parentAgentId }
    }

    func findAllDescendants(_ parentAgentId: AgentID) throws -> [Agent] {
        var allDescendants: [Agent] = []
        var queue = [parentAgentId]

        while !queue.isEmpty {
            let currentId = queue.removeFirst()
            let children = try findByParent(currentId)
            allDescendants.append(contentsOf: children)
            queue.append(contentsOf: children.map { $0.id })
        }

        return allDescendants
    }

    func findRootAgents() throws -> [Agent] {
        agents.values.filter { $0.parentAgentId == nil }
    }

    func findLocked(byAuditId auditId: InternalAuditID?) throws -> [Agent] {
        if let auditId = auditId {
            return agents.values.filter { $0.isLocked && $0.lockedByAuditId == auditId }
        }
        return agents.values.filter { $0.isLocked }
    }

    func save(_ agent: Agent) throws {
        agents[agent.id] = agent
    }

    func delete(_ id: AgentID) throws {
        agents.removeValue(forKey: id)
    }
}

final class MockTaskRepository: TaskRepositoryProtocol {
    var tasks: [TaskID: Task] = [:]

    func findById(_ id: TaskID) throws -> Task? {
        tasks[id]
    }

    func findAll(projectId: ProjectID) throws -> [Task] {
        tasks.values.filter { $0.projectId == projectId }
    }

    func findByProject(_ projectId: ProjectID, status: TaskStatus?) throws -> [Task] {
        var result = tasks.values.filter { $0.projectId == projectId }
        if let status = status {
            result = result.filter { $0.status == status }
        }
        return Array(result)
    }

    func findByAssignee(_ agentId: AgentID) throws -> [Task] {
        tasks.values.filter { $0.assigneeId == agentId }
    }

    func findPendingByAssignee(_ agentId: AgentID) throws -> [Task] {
        tasks.values.filter { $0.assigneeId == agentId && $0.status == .inProgress }
    }

    func findByStatus(_ status: TaskStatus, projectId: ProjectID) throws -> [Task] {
        tasks.values.filter { $0.projectId == projectId && $0.status == status }
    }

    func findLocked(byAuditId auditId: InternalAuditID?) throws -> [Task] {
        if let auditId = auditId {
            return tasks.values.filter { $0.isLocked && $0.lockedByAuditId == auditId }
        }
        return tasks.values.filter { $0.isLocked }
    }

    func save(_ task: Task) throws {
        tasks[task.id] = task
    }

    func delete(_ id: TaskID) throws {
        tasks.removeValue(forKey: id)
    }
}

final class MockSessionRepository: SessionRepositoryProtocol {
    var sessions: [SessionID: Session] = [:]

    func findById(_ id: SessionID) throws -> Session? {
        sessions[id]
    }

    func findActive(agentId: AgentID) throws -> Session? {
        sessions.values.first { $0.agentId == agentId && $0.status == .active }
    }

    func findByProject(_ projectId: ProjectID) throws -> [Session] {
        sessions.values.filter { $0.projectId == projectId }
    }

    func findByAgent(_ agentId: AgentID) throws -> [Session] {
        sessions.values.filter { $0.agentId == agentId }
    }

    func save(_ session: Session) throws {
        sessions[session.id] = session
    }

    func delete(_ id: SessionID) throws {
        sessions.removeValue(forKey: id)
    }

    func findActiveByProject(_ projectId: ProjectID) throws -> [Session] {
        sessions.values.filter { $0.projectId == projectId && $0.status == .active }
    }

    func findActiveByAgentAndProject(agentId: AgentID, projectId: ProjectID) throws -> [Session] {
        sessions.values.filter { $0.agentId == agentId && $0.projectId == projectId && $0.status == .active }
    }
}

final class MockContextRepository: ContextRepositoryProtocol {
    var contexts: [ContextID: Context] = [:]

    func findById(_ id: ContextID) throws -> Context? {
        contexts[id]
    }

    func findByTask(_ taskId: TaskID) throws -> [Context] {
        contexts.values.filter { $0.taskId == taskId }
    }

    func findBySession(_ sessionId: SessionID) throws -> [Context] {
        contexts.values.filter { $0.sessionId == sessionId }
    }

    func findLatest(taskId: TaskID) throws -> Context? {
        contexts.values
            .filter { $0.taskId == taskId }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func save(_ context: Context) throws {
        contexts[context.id] = context
    }

    func delete(_ id: ContextID) throws {
        contexts.removeValue(forKey: id)
    }
}

final class MockEventRepository: EventRepositoryProtocol {
    var events: [EventID: StateChangeEvent] = [:]

    func findByProject(_ projectId: ProjectID, limit: Int?) throws -> [StateChangeEvent] {
        var result = events.values.filter { $0.projectId == projectId }
        if let limit = limit {
            result = Array(result.prefix(limit))
        }
        return result
    }

    func findByEntity(type: EntityType, id: String) throws -> [StateChangeEvent] {
        events.values.filter { $0.entityType == type && $0.entityId == id }
    }

    func findRecent(projectId: ProjectID, since: Date) throws -> [StateChangeEvent] {
        events.values.filter { $0.projectId == projectId && $0.timestamp >= since }
    }

    func save(_ event: StateChangeEvent) throws {
        events[event.id] = event
    }
}

final class MockWorkflowTemplateRepository: WorkflowTemplateRepositoryProtocol {
    var templates: [WorkflowTemplateID: WorkflowTemplate] = [:]

    func findById(_ id: WorkflowTemplateID) throws -> WorkflowTemplate? {
        templates[id]
    }

    func findByProject(_ projectId: ProjectID, includeArchived: Bool) throws -> [WorkflowTemplate] {
        var result = templates.values.filter { $0.projectId == projectId }
        if !includeArchived {
            result = result.filter { $0.status == .active }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    func findActiveByProject(_ projectId: ProjectID) throws -> [WorkflowTemplate] {
        try findByProject(projectId, includeArchived: false)
    }

    func findAllActive() throws -> [WorkflowTemplate] {
        templates.values.filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ template: WorkflowTemplate) throws {
        templates[template.id] = template
    }

    func delete(_ id: WorkflowTemplateID) throws {
        templates.removeValue(forKey: id)
    }
}

final class MockTemplateTaskRepository: TemplateTaskRepositoryProtocol {
    var tasks: [TemplateTaskID: TemplateTask] = [:]

    func findById(_ id: TemplateTaskID) throws -> TemplateTask? {
        tasks[id]
    }

    func findByTemplate(_ templateId: WorkflowTemplateID) throws -> [TemplateTask] {
        tasks.values
            .filter { $0.templateId == templateId }
            .sorted { $0.order < $1.order }
    }

    func save(_ task: TemplateTask) throws {
        tasks[task.id] = task
    }

    func delete(_ id: TemplateTaskID) throws {
        tasks.removeValue(forKey: id)
    }

    func deleteByTemplate(_ templateId: WorkflowTemplateID) throws {
        let toDelete = tasks.values.filter { $0.templateId == templateId }.map { $0.id }
        for id in toDelete {
            tasks.removeValue(forKey: id)
        }
    }
}

final class MockInternalAuditRepository: InternalAuditRepositoryProtocol {
    var audits: [InternalAuditID: InternalAudit] = [:]

    func findById(_ id: InternalAuditID) throws -> InternalAudit? {
        audits[id]
    }

    func findAll(includeInactive: Bool) throws -> [InternalAudit] {
        var result = Array(audits.values)
        if !includeInactive {
            result = result.filter { $0.status == .active }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    func findActive() throws -> [InternalAudit] {
        try findAll(includeInactive: false)
    }

    func save(_ audit: InternalAudit) throws {
        audits[audit.id] = audit
    }

    func delete(_ id: InternalAuditID) throws {
        audits.removeValue(forKey: id)
    }
}

final class MockAuditRuleRepository: AuditRuleRepositoryProtocol {
    var rules: [AuditRuleID: AuditRule] = [:]

    func findById(_ id: AuditRuleID) throws -> AuditRule? {
        rules[id]
    }

    func findByAudit(_ auditId: InternalAuditID) throws -> [AuditRule] {
        rules.values
            .filter { $0.auditId == auditId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func findEnabled(auditId: InternalAuditID) throws -> [AuditRule] {
        rules.values
            .filter { $0.auditId == auditId && $0.isEnabled }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func findByTriggerType(_ triggerType: TriggerType) throws -> [AuditRule] {
        rules.values
            .filter { $0.triggerType == triggerType }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ rule: AuditRule) throws {
        rules[rule.id] = rule
    }

    func delete(_ id: AuditRuleID) throws {
        rules.removeValue(forKey: id)
    }
}

// MARK: - Authentication Mock Repositories (Phase 3-1)

final class MockAgentCredentialRepository: AgentCredentialRepositoryProtocol {
    var credentials: [AgentCredentialID: AgentCredential] = [:]

    func findById(_ id: AgentCredentialID) throws -> AgentCredential? {
        credentials[id]
    }

    func findByAgentId(_ agentId: AgentID) throws -> AgentCredential? {
        credentials.values.first { $0.agentId == agentId }
    }

    func save(_ credential: AgentCredential) throws {
        credentials[credential.id] = credential
    }

    func delete(_ id: AgentCredentialID) throws {
        credentials.removeValue(forKey: id)
    }
}

final class MockAgentSessionRepository: AgentSessionRepositoryProtocol {
    var sessions: [AgentSessionID: AgentSession] = [:]

    func findById(_ id: AgentSessionID) throws -> AgentSession? {
        sessions[id]
    }

    func findByToken(_ token: String) throws -> AgentSession? {
        sessions.values.first { $0.token == token && !$0.isExpired }
    }

    func findByAgentId(_ agentId: AgentID) throws -> [AgentSession] {
        sessions.values.filter { $0.agentId == agentId }
    }

    func findByAgentIdAndProjectId(_ agentId: AgentID, projectId: ProjectID) throws -> [AgentSession] {
        sessions.values.filter { $0.agentId == agentId && $0.projectId == projectId }
    }

    func findByProjectId(_ projectId: ProjectID) throws -> [AgentSession] {
        Array(sessions.values.filter { $0.projectId == projectId })
    }

    func save(_ session: AgentSession) throws {
        sessions[session.id] = session
    }

    func delete(_ id: AgentSessionID) throws {
        sessions.removeValue(forKey: id)
    }

    func deleteByToken(_ token: String) throws {
        let toDelete = sessions.values.filter { $0.token == token }.map { $0.id }
        for id in toDelete {
            sessions.removeValue(forKey: id)
        }
    }

    func deleteByAgentId(_ agentId: AgentID) throws {
        let toDelete = sessions.values.filter { $0.agentId == agentId }.map { $0.id }
        for id in toDelete {
            sessions.removeValue(forKey: id)
        }
    }

    func deleteExpired() throws {
        let toDelete = sessions.values.filter { $0.isExpired }.map { $0.id }
        for id in toDelete {
            sessions.removeValue(forKey: id)
        }
    }

    func countActiveSessions(agentId: AgentID) throws -> Int {
        sessions.values.filter { $0.agentId == agentId && !$0.isExpired }.count
    }

    func findActiveSessions(agentId: AgentID) throws -> [AgentSession] {
        Array(sessions.values.filter { $0.agentId == agentId && !$0.isExpired })
    }

    func countActiveSessionsByPurpose(agentId: AgentID) throws -> [AgentPurpose: Int] {
        var counts: [AgentPurpose: Int] = [.chat: 0, .task: 0]
        for session in sessions.values where session.agentId == agentId && !session.isExpired {
            counts[session.purpose, default: 0] += 1
        }
        return counts
    }

    func updateLastActivity(token: String, at date: Date) throws {
        if let id = sessions.values.first(where: { $0.token == token })?.id {
            var session = sessions[id]!
            session.lastActivityAt = date
            sessions[id] = session
        }
    }

    func updateState(token: String, state: SessionState) throws {
        if let id = sessions.values.first(where: { $0.token == token })?.id {
            var session = sessions[id]!
            session.state = state
            sessions[id] = session
        }
    }
}

final class MockExecutionLogRepository: ExecutionLogRepositoryProtocol {
    var logs: [ExecutionLogID: ExecutionLog] = [:]

    func findById(_ id: ExecutionLogID) throws -> ExecutionLog? {
        logs[id]
    }

    func findByTaskId(_ taskId: TaskID) throws -> [ExecutionLog] {
        logs.values.filter { $0.taskId == taskId }.sorted { $0.startedAt > $1.startedAt }
    }

    func findByAgentId(_ agentId: AgentID) throws -> [ExecutionLog] {
        logs.values.filter { $0.agentId == agentId }.sorted { $0.startedAt > $1.startedAt }
    }

    func findByAgentId(_ agentId: AgentID, limit: Int?, offset: Int?) throws -> [ExecutionLog] {
        var result = logs.values.filter { $0.agentId == agentId }.sorted { $0.startedAt > $1.startedAt }
        if let offset = offset {
            result = Array(result.dropFirst(offset))
        }
        if let limit = limit {
            result = Array(result.prefix(limit))
        }
        return result
    }

    func findRunning(agentId: AgentID) throws -> [ExecutionLog] {
        logs.values.filter { $0.agentId == agentId && $0.status == .running }.sorted { $0.startedAt > $1.startedAt }
    }

    func findLatestByAgentAndTask(agentId: AgentID, taskId: TaskID) throws -> ExecutionLog? {
        logs.values
            .filter { $0.agentId == agentId && $0.taskId == taskId }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    func save(_ log: ExecutionLog) throws {
        logs[log.id] = log
    }

    func delete(_ id: ExecutionLogID) throws {
        logs.removeValue(forKey: id)
    }
}
