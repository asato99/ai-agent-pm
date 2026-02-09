// Sources/App/Features/TaskDetail/TaskDetailComponents.swift
// タスク詳細のサブコンポーネント（Badge, Card, Row, Dialog）

import SwiftUI
import Domain

// MARK: - StatusBadge

struct StatusBadge: View {
    let status: TaskStatus

    var color: Color {
        switch status {
        case .backlog: return .gray
        case .todo: return .blue
        case .inProgress: return .orange
        case .blocked: return .red
        case .done: return .green
        case .cancelled: return .gray
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - ContextCard

struct ContextCard: View {
    let context: Context

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.createdAt, style: .date)
                Text(context.createdAt, style: .time)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let progress = context.progress {
                Label(progress, systemImage: "arrow.right")
                    .font(.subheadline)
            }

            if let findings = context.findings {
                Label(findings, systemImage: "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let blockers = context.blockers {
                Label(blockers, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - HandoffCard

struct HandoffCard: View {
    let handoff: Handoff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(handoff.createdAt, style: .date)
                Text(handoff.createdAt, style: .time)
                Spacer()
                if handoff.isAccepted {
                    Text("Accepted")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                } else {
                    Text("Pending")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(handoff.summary)
                .font(.subheadline)

            if let context = handoff.context {
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let recommendations = handoff.recommendations {
                Label(recommendations, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - HistoryEventRow

struct HistoryEventRow: View {
    let event: StateChangeEvent

    var eventIcon: String {
        switch event.eventType {
        case .created: return "plus.circle"
        case .updated: return "pencil.circle"
        case .deleted: return "trash.circle"
        case .statusChanged: return "arrow.triangle.2.circlepath"
        case .assigned: return "person.badge.plus"
        case .unassigned: return "person.badge.minus"
        case .started: return "play.circle"
        case .completed: return "checkmark.circle"
        case .kicked: return "bolt.circle"
        case .notified: return "bell.badge"
        }
    }

    var eventColor: Color {
        switch event.eventType {
        case .created: return .green
        case .deleted: return .red
        case .completed: return .green
        case .statusChanged: return .blue
        case .assigned, .unassigned: return .purple
        case .kicked: return .orange
        case .notified: return .green
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: eventIcon)
                .foregroundStyle(eventColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.eventType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let previousState = event.previousState, let newState = event.newState {
                    Text("\(previousState) → \(newState)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let reason = event.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(event.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TaskExecutionLogRow (Phase 3-4)

struct TaskExecutionLogRow: View {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Agent: \(log.agentId.value)")
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
                }
            }

            if let duration = log.durationSeconds {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Duration: \(String(format: "%.1f", duration))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let exitCode = log.exitCode {
                HStack {
                    Image(systemName: exitCode == 0 ? "checkmark.seal" : "xmark.seal")
                        .foregroundStyle(exitCode == 0 ? .green : .red)
                    Text("Exit Code: \(exitCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let logPath = log.logFilePath {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text(logPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityIdentifier("LogFilePath_\(log.id.value)")
            }

            if let error = log.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Approval Status Badge (Detailed)
// 参照: docs/design/TASK_REQUEST_APPROVAL.md

struct ApprovalStatusDetailBadge: View {
    let status: ApprovalStatus

    var text: String {
        switch status {
        case .pendingApproval:
            return "🔔 承認待ち"
        case .rejected:
            return "❌ 却下"
        case .approved:
            return "✅ 承認済み"
        }
    }

    var color: Color {
        switch status {
        case .pendingApproval:
            return .orange
        case .rejected:
            return .gray
        case .approved:
            return .green
        }
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.semibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Reject Task Dialog
// 参照: docs/design/TASK_REQUEST_APPROVAL.md

struct RejectTaskDialog: View {
    let taskTitle: String
    @Binding var reason: String
    let onReject: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("タスクを却下")
                .font(.headline)

            Text("「\(taskTitle)」を却下しますか？")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("却下理由（任意）", text: $reason, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .accessibilityIdentifier("RejectReasonField")

            HStack(spacing: 16) {
                Button("キャンセル") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("CancelRejectButton")

                Button("却下する") {
                    onReject()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("ConfirmRejectButton")
            }
        }
        .padding(24)
        .frame(minWidth: 300)
        .accessibilityIdentifier("RejectTaskDialog")
    }
}
