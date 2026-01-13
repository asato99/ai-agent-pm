// Sources/App/Features/TaskBoard/Components/AgentAvatarButton.swift
// 参照: docs/design/CHAT_FEATURE.md - AgentAvatarButton デザイン

import SwiftUI
import Domain

/// エージェントのアバターボタン
/// クリックでチャット画面を開く
struct AgentAvatarButton: View {
    let agent: Agent
    let projectId: ProjectID
    let activeSessionCount: Int
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

    /// セッション数に基づく色分け
    /// - 0: グレー (待機中)
    /// - 1: グリーン (実行中)
    /// - 2+: オレンジ (複数実行中)
    private var statusColor: Color {
        switch activeSessionCount {
        case 0: return .gray
        case 1: return .green
        default: return .orange
        }
    }

    private var backgroundColor: Color {
        if isHovered {
            return statusColor.opacity(0.3)
        }
        return statusColor.opacity(0.1)
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
        // 待機中 (0セッション)
        AgentAvatarButton(
            agent: Agent(
                id: AgentID.generate(),
                name: "Claude",
                role: "Developer",
                type: .ai,
                status: .active
            ),
            projectId: ProjectID.generate(),
            activeSessionCount: 0,
            onTap: {}
        )

        // 実行中 (1セッション)
        AgentAvatarButton(
            agent: Agent(
                id: AgentID.generate(),
                name: "GPT-4",
                role: "Reviewer",
                type: .ai,
                status: .active
            ),
            projectId: ProjectID.generate(),
            activeSessionCount: 1,
            onTap: {}
        )

        // 複数実行中 (2セッション)
        AgentAvatarButton(
            agent: Agent(
                id: AgentID.generate(),
                name: "Human User",
                role: "Manager",
                type: .human,
                status: .active
            ),
            projectId: ProjectID.generate(),
            activeSessionCount: 2,
            onTap: {}
        )
    }
    .padding()
}
#endif
