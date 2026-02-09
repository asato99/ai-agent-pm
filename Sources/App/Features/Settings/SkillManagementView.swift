// Sources/App/Features/Settings/SkillManagementView.swift
// スキル管理ビュー（一覧・削除）
// エディタ: SkillEditorView.swift
// 参照: docs/design/AGENT_SKILLS.md - Section 4.1

import SwiftUI
import Domain
import UseCase

// Swift.Task と Domain.Task の名前衝突を解決
private typealias AsyncTask = _Concurrency.Task

// MARK: - SkillManagementView

struct SkillManagementView: View {
    @EnvironmentObject var container: DependencyContainer

    @State private var skills: [SkillDefinition] = []
    @State private var isLoading = false
    @State private var showEditor = false
    @State private var editingSkill: SkillDefinition?
    @State private var showDeleteConfirmation = false
    @State private var skillToDelete: SkillDefinition?
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            // ツールバー
            HStack {
                Text("Skills")
                    .font(.headline)
                Spacer()
                Button {
                    editingSkill = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("AddSkillButton")
                .help("Add Skill")
            }
            .padding()

            Divider()

            // スキル一覧
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if skills.isEmpty {
                emptyStateView
            } else {
                skillListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadSkills()
        }
        .sheet(isPresented: $showEditor) {
            SkillEditorView(
                skill: editingSkill,
                onSave: { savedSkill in
                    showEditor = false
                    AsyncTask {
                        await loadSkills()
                    }
                },
                onCancel: {
                    showEditor = false
                }
            )
            .environmentObject(container)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .confirmationDialog(
            "Delete Skill",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let skill = skillToDelete {
                    AsyncTask { await deleteSkill(skill) }
                }
            }
            Button("Cancel", role: .cancel) {
                skillToDelete = nil
            }
        } message: {
            if let skill = skillToDelete {
                Text("Are you sure you want to delete '\(skill.name)'? This action cannot be undone.")
            }
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Skills")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Create skills to extend agent capabilities.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Add Skill") {
                editingSkill = nil
                showEditor = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var skillListView: some View {
        List {
            ForEach(skills) { skill in
                SkillRowView(skill: skill)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingSkill = skill
                        showEditor = true
                    }
                    .contextMenu {
                        Button {
                            editingSkill = skill
                            showEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            skillToDelete = skill
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Actions

    @MainActor
    private func loadSkills() async {
        isLoading = true
        defer { isLoading = false }

        do {
            skills = try container.skillDefinitionUseCases.findAll()
        } catch {
            errorMessage = "Failed to load skills: \(error.localizedDescription)"
            showError = true
        }
    }

    @MainActor
    private func deleteSkill(_ skill: SkillDefinition) async {
        do {
            try container.skillDefinitionUseCases.delete(skill.id)
            await loadSkills()
        } catch let error as SkillError {
            errorMessage = error.errorDescription
            showError = true
        } catch {
            errorMessage = "Failed to delete skill: \(error.localizedDescription)"
            showError = true
        }
        skillToDelete = nil
    }
}

// MARK: - SkillRowView

struct SkillRowView: View {
    let skill: SkillDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(skill.name)
                    .font(.headline)

                Spacer()

                Text(skill.directoryName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .cornerRadius(4)
            }

            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("SkillRow-\(skill.directoryName)")
    }
}
