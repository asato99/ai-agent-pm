// Sources/App/Features/TaskBoard/Components/AgentAvatarButton.swift
// 参照: docs/design/CHAT_FEATURE.md - AgentAvatarButton デザイン

import SwiftUI
import Domain

/// エージェントのアバターボタン
/// クリックでチャット画面を開く
struct AgentAvatarButton: View {
    let agent: Agent
    let projectId: ProjectID
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                // アイコン (AI or Human)
                Text(agent.type == .ai ? "🤖" : "👤")
                    .font(.caption2)

                // 名前
                Text(agent.name)
                    .font(.caption)
                    .lineLimit(1)

                // ステータスインジケーター
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityIdentifier("AgentAvatarButton-\(agent.id.value)")
    }

    // MARK: - Styling

    private var statusColor: Color {
        switch agent.status {
        case .active:
            return .green
        case .inactive:
            return .gray
        case .suspended:
            return .orange
        case .archived:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        if isHovered {
            return statusBackgroundColor.opacity(0.3)
        }
        return statusBackgroundColor.opacity(0.1)
    }

    private var statusBackgroundColor: Color {
        switch agent.status {
        case .active:
            return .green
        case .inactive:
            return .gray
        case .suspended:
            return .orange
        case .archived:
            return .secondary
        }
    }

    private var borderColor: Color {
        if isHovered {
            return statusColor
        }
        return statusColor.opacity(0.5)
    }
}

#if DEBUG
#Preview {
    HStack {
        AgentAvatarButton(
            agent: Agent(
                id: AgentID.generate(),
                name: "Claude",
                role: "Developer",
                type: .ai,
                status: .active
            ),
            projectId: ProjectID.generate(),
            onTap: {}
        )

        AgentAvatarButton(
            agent: Agent(
                id: AgentID.generate(),
                name: "Human User",
                role: "Manager",
                type: .human,
                status: .inactive
            ),
            projectId: ProjectID.generate(),
            onTap: {}
        )
    }
    .padding()
}
#endif
