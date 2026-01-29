// Sources/App/Features/AgentManagement/AgentSkillAssignmentView.swift
// エージェントスキル割り当てビュー
// 参照: docs/design/AGENT_SKILLS.md - Section 4.2

import SwiftUI
import Domain

// MARK: - AgentSkillAssignmentView

/// エージェントにスキルを割り当てるシート
struct AgentSkillAssignmentView: View {
    @EnvironmentObject var container: DependencyContainer

    let agent: Agent
    let onSave: ([SkillID]) -> Void
    let onCancel: () -> Void

    @State private var allSkills: [SkillDefinition] = []
    @State private var selectedSkillIds: Set<SkillID> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("Skill Assignment")
                    .font(.headline)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // エージェント情報
            HStack(spacing: 12) {
                Image(systemName: agent.type == .human ? "person.circle.fill" : "cpu.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(agent.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            // スキル一覧
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allSkills.isEmpty {
                emptyStateView
            } else {
                skillListView
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }

            Divider()

            // フッター
            HStack {
                Text("\(selectedSkillIds.count) skill(s) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(Array(selectedSkillIds))
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("SaveSkillAssignmentButton")
            }
            .padding()
        }
        .frame(width: 450, height: 500)
        .task {
            await loadData()
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Skills Available")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Create skills in Settings → Skills to assign them to agents.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var skillListView: some View {
        List {
            ForEach(allSkills) { skill in
                SkillCheckboxRow(
                    skill: skill,
                    isSelected: selectedSkillIds.contains(skill.id),
                    onToggle: { isSelected in
                        if isSelected {
                            selectedSkillIds.insert(skill.id)
                        } else {
                            selectedSkillIds.remove(skill.id)
                        }
                    }
                )
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 全スキルを取得
            allSkills = try container.skillDefinitionUseCases.findAll()

            // 現在の割り当てを取得
            let assignedSkills = try container.agentSkillUseCases.getAgentSkills(agent.id)
            selectedSkillIds = Set(assignedSkills.map { $0.id })
        } catch {
            errorMessage = "Failed to load skills: \(error.localizedDescription)"
        }
    }
}

// MARK: - SkillCheckboxRow

struct SkillCheckboxRow: View {
    let skill: SkillDefinition
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(skill.directoryName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .cornerRadius(4)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle(!isSelected)
        }
        .accessibilityIdentifier("SkillCheckbox-\(skill.directoryName)")
    }
}

// MARK: - AgentSkillsSection

/// AgentDetailView用のスキルセクション
struct AgentSkillsSection: View {
    let assignedSkills: [SkillDefinition]
    let onManageSkills: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Skills")
                    .font(.headline)

                Spacer()

                Button {
                    onManageSkills()
                } label: {
                    Label("Manage", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ManageSkillsButton")
            }

            if assignedSkills.isEmpty {
                Text("No skills assigned")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(assignedSkills) { skill in
                        SkillBadge(skill: skill)
                    }
                }
            }
        }
        .accessibilityIdentifier("AgentSkillsSection")
    }
}

// MARK: - SkillBadge

struct SkillBadge: View {
    let skill: SkillDefinition

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wand.and.stars")
                .font(.caption2)

            Text(skill.name)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.purple.opacity(0.15))
        .foregroundStyle(.purple)
        .clipShape(Capsule())
        .accessibilityIdentifier("SkillBadge-\(skill.directoryName)")
    }
}

// MARK: - FlowLayout

/// 水平に並べて折り返すレイアウト
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var positions: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
