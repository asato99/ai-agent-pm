// Sources/App/Features/Settings/SkillManagementView.swift
// スキル管理ビュー
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

// MARK: - SkillEditorView

struct SkillEditorView: View {
    @EnvironmentObject var container: DependencyContainer

    let skill: SkillDefinition?
    let onSave: (SkillDefinition) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var directoryName: String = ""
    @State private var content: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { skill != nil }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        SkillDefinition.isValidDirectoryName(directoryName) &&
        description.count <= SkillDefinition.maxDescriptionLength &&
        content.utf8.count <= SkillDefinition.maxArchiveSize  // Archive size includes ZIP overhead
    }

    private var directoryNameValidationError: String? {
        if directoryName.isEmpty { return nil }
        if !SkillDefinition.isValidDirectoryName(directoryName) {
            return "Must be 2-64 characters: lowercase letters, numbers, hyphens only"
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text(isEditing ? "Edit Skill" : "New Skill")
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

            // フォーム
            Form {
                Section("Basic Information") {
                    TextField("Skill Name", text: $name)
                        .accessibilityIdentifier("SkillNameField")

                    TextField("Description (optional)", text: $description)
                        .accessibilityIdentifier("SkillDescriptionField")

                    if description.count > 200 {
                        Text("\(description.count)/\(SkillDefinition.maxDescriptionLength) characters")
                            .font(.caption)
                            .foregroundStyle(description.count > SkillDefinition.maxDescriptionLength ? .red : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Directory Name", text: $directoryName)
                            .accessibilityIdentifier("SkillDirectoryNameField")
                            .textCase(.lowercase)
                            .onChange(of: directoryName) { _, newValue in
                                // 自動的に小文字に変換
                                let lowercased = newValue.lowercased()
                                if lowercased != newValue {
                                    directoryName = lowercased
                                }
                            }

                        if let error = directoryNameValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("Example: code-review, test-creation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Content (SKILL.md)") {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .accessibilityIdentifier("SkillContentEditor")

                    if content.utf8.count > 900_000 {
                        Text("\(content.utf8.count / 1024)KB / 1MB")
                            .font(.caption)
                            .foregroundStyle(content.utf8.count > SkillDefinition.maxArchiveSize ? .red : .secondary)
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // フッター
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveSkill()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isFormValid || isSaving)
                .accessibilityIdentifier("SaveSkillButton")
            }
            .padding()
        }
        .frame(width: 600, height: 550)
        .onAppear {
            if let skill = skill {
                name = skill.name
                description = skill.description
                directoryName = skill.directoryName
                // ZIPアーカイブからSKILL.md内容を抽出
                content = container.skillArchiveService.getSkillMdContent(from: skill.archiveData) ?? ""
            } else {
                // デフォルトテンプレート
                content = """
                ---
                name: skill-name
                description: Brief description of the skill
                ---

                # Skill Name

                ## Instructions

                Describe what this skill does and how it should be used.

                ## Steps

                1. First step
                2. Second step
                3. Third step
                """
            }
        }
    }

    private func saveSkill() {
        isSaving = true
        errorMessage = nil

        do {
            let savedSkill: SkillDefinition
            if let existingSkill = skill {
                // 更新（名前・説明のみ変更可能）
                var updatedSkill = try container.skillDefinitionUseCases.update(
                    id: existingSkill.id,
                    name: name,
                    description: description
                )

                // コンテンツが変更された場合はreimport
                let currentContent = container.skillArchiveService.getSkillMdContent(from: existingSkill.archiveData) ?? ""
                if content != currentContent {
                    let archiveData = container.skillArchiveService.createArchiveFromContent(content)
                    updatedSkill = try container.skillDefinitionUseCases.reimport(
                        id: existingSkill.id,
                        archiveData: archiveData
                    )
                }
                savedSkill = updatedSkill
            } else {
                // 新規作成（SKILL.mdからZIPアーカイブを生成）
                let archiveData = container.skillArchiveService.createArchiveFromContent(content)
                savedSkill = try container.skillDefinitionUseCases.create(
                    name: name,
                    description: description,
                    directoryName: directoryName,
                    archiveData: archiveData
                )
            }
            onSave(savedSkill)
        } catch let error as SkillError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}
