// Sources/App/Features/TaskBoard/Components/AssignedAgentsRow.swift
// 参照: docs/design/CHAT_FEATURE.md - AssignedAgentsRow

import SwiftUI
import Domain

/// 割り当てられたエージェント一覧を表示する行
struct AssignedAgentsRow: View {
    let projectId: ProjectID
    let agents: [Agent]
    let sessionCounts: [AgentID: Int]
    let onAgentTap: (AgentID) -> Void

    /// 表示上限
    private let maxVisibleAgents = 5

    var body: some View {
        HStack(spacing: 8) {
            // ラベル
            Label("Agents:", systemImage: "person.2")
                .font(.caption)
                .foregroundStyle(.secondary)

            if agents.isEmpty {
                Text("No agents assigned")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                // エージェントアバター一覧
                HStack(spacing: 4) {
                    ForEach(visibleAgents) { agent in
                        AgentAvatarButton(
                            agent: agent,
                            projectId: projectId,
                            activeSessionCount: sessionCounts[agent.id] ?? 0,
                            onTap: { onAgentTap(agent.id) }
                        )
                    }

                    // 表示しきれない分の表示
                    if hiddenCount > 0 {
                        Text("+\(hiddenCount) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(.quaternary)
                            )
                    }
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("AssignedAgentsRow")
    }

    // MARK: - Computed Properties

    private var visibleAgents: [Agent] {
        Array(agents.prefix(maxVisibleAgents))
    }

    private var hiddenCount: Int {
        max(0, agents.count - maxVisibleAgents)
    }
}

#if DEBUG
#Preview {
    let agent1 = AgentID.generate()
    let agent2 = AgentID.generate()
    let agent3 = AgentID.generate()

    return VStack(spacing: 20) {
        // エージェントあり (セッション数バリエーション)
        AssignedAgentsRow(
            projectId: ProjectID.generate(),
            agents: [
                Agent(
                    id: agent1,
                    name: "Claude",
                    role: "Developer",
                    type: .ai,
                    status: .active
                ),
                Agent(
                    id: agent2,
                    name: "GPT-4",
                    role: "Reviewer",
                    type: .ai,
                    status: .active
                ),
                Agent(
                    id: agent3,
                    name: "Alice",
                    role: "Manager",
                    type: .human,
                    status: .active
                )
            ],
            sessionCounts: [agent1: 0, agent2: 1, agent3: 2],
            onAgentTap: { _ in }
        )

        // エージェントなし
        AssignedAgentsRow(
            projectId: ProjectID.generate(),
            agents: [],
            sessionCounts: [:],
            onAgentTap: { _ in }
        )
    }
    .padding()
}
#endif
