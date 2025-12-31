// Sources/Infrastructure/Repositories/EventRepository.swift
// 参照: docs/prd/STATE_HISTORY.md - イベントソーシング

import Foundation
import GRDB
import Domain

// MARK: - EventRecord

struct EventRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "state_change_events"

    var id: String
    var projectId: String
    var entityType: String
    var entityId: String
    var eventType: String
    var agentId: String?
    var sessionId: String?
    var previousState: String?
    var newState: String?
    var reason: String?
    var metadata: String?
    var timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case eventType = "event_type"
        case agentId = "agent_id"
        case sessionId = "session_id"
        case previousState = "previous_state"
        case newState = "new_state"
        case reason
        case metadata
        case timestamp
    }

    func toDomain() -> StateChangeEvent {
        var meta: [String: String]?
        if let metadataJson = metadata,
           let data = metadataJson.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
            meta = parsed
        }

        return StateChangeEvent(
            id: EventID(value: id),
            projectId: ProjectID(value: projectId),
            entityType: EntityType(rawValue: entityType) ?? .task,
            entityId: entityId,
            eventType: EventType(rawValue: eventType) ?? .updated,
            agentId: agentId.map { AgentID(value: $0) },
            sessionId: sessionId.map { SessionID(value: $0) },
            previousState: previousState,
            newState: newState,
            reason: reason,
            metadata: meta,
            timestamp: timestamp
        )
    }

    static func fromDomain(_ event: StateChangeEvent) -> EventRecord {
        var metaJson: String?
        if let metadata = event.metadata,
           let data = try? JSONEncoder().encode(metadata) {
            metaJson = String(data: data, encoding: .utf8)
        }

        return EventRecord(
            id: event.id.value,
            projectId: event.projectId.value,
            entityType: event.entityType.rawValue,
            entityId: event.entityId,
            eventType: event.eventType.rawValue,
            agentId: event.agentId?.value,
            sessionId: event.sessionId?.value,
            previousState: event.previousState,
            newState: event.newState,
            reason: event.reason,
            metadata: metaJson,
            timestamp: event.timestamp
        )
    }
}

// MARK: - EventRepository

public final class EventRepository: EventRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findByProject(_ projectId: ProjectID, limit: Int?) throws -> [StateChangeEvent] {
        try db.read { db in
            var request = EventRecord
                .filter(Column("project_id") == projectId.value)
                .order(Column("timestamp").desc)

            if let limit = limit {
                request = request.limit(limit)
            }

            return try request.fetchAll(db).map { $0.toDomain() }
        }
    }

    public func findByEntity(type: EntityType, id: String) throws -> [StateChangeEvent] {
        try db.read { db in
            try EventRecord
                .filter(Column("entity_type") == type.rawValue)
                .filter(Column("entity_id") == id)
                .order(Column("timestamp").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findRecent(projectId: ProjectID, since: Date) throws -> [StateChangeEvent] {
        try db.read { db in
            try EventRecord
                .filter(Column("project_id") == projectId.value)
                .filter(Column("timestamp") >= since)
                .order(Column("timestamp").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ event: StateChangeEvent) throws {
        try db.write { db in
            try EventRecord.fromDomain(event).save(db)
        }
    }
}
