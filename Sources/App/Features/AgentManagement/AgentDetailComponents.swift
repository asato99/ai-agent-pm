// Sources/App/Features/AgentManagement/AgentDetailComponents.swift
// エージェント詳細のサブコンポーネント（Badge, Row, StatItem）

import SwiftUI
import Domain

// MARK: - ExecutionLogRow (Phase 3-4)

struct ExecutionLogRow: View {
    let log: ExecutionLog

    var statusColor: Color {
        switch log.status {
        case .running: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    var statusIcon: String {
        switch log.status {
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Task: \(log.taskId.value)")
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer()

                    Text(log.status.rawValue.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.15))
                        .foregroundStyle(statusColor)
                        .clipShape(Capsule())
                }

                HStack {
                    Text(log.startedAt, style: .date)
                    Text(log.startedAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let duration = log.durationSeconds {
                    Text("Duration: \(String(format: "%.1f", duration))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = log.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - StatItem

struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - TaskRow

struct TaskRow: View {
    let task: Task

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(task.title)
                    .font(.subheadline)
                Text(task.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PriorityBadge(priority: task.priority)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - SessionRow

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.startedAt, style: .date)
                    .font(.subheadline)
                Text(session.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let endedAt = session.endedAt {
                Text(endedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - RoleTypeBadge

struct RoleTypeBadge: View {
    let roleType: AgentRoleType

    var body: some View {
        Text(roleType.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.15))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
    }
}

// MARK: - AgentTypeBadge

struct AgentTypeBadge: View {
    let type: AgentType

    var body: some View {
        Text(type == .human ? "Human" : "AI")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.purple.opacity(0.15))
            .foregroundStyle(.purple)
            .clipShape(Capsule())
    }
}

// MARK: - AgentStatusBadge

struct AgentStatusBadge: View {
    let status: AgentStatus

    var color: Color {
        switch status {
        case .active: return .green
        case .inactive: return .gray
        case .suspended: return .orange
        case .archived: return .red
        }
    }

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
