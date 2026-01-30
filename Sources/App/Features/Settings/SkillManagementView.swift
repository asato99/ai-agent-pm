// Sources/App/Features/Settings/SkillManagementView.swift
// スキル管理ビュー
// 参照: docs/design/AGENT_SKILLS.md - Section 4.1

import SwiftUI
import UniformTypeIdentifiers
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

    // 基本情報
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var directoryName: String = ""

    // ファイル管理
    @State private var files: [String: String] = [:]
    @State private var selectedFile: String? = nil
    @State private var binaryFiles: Set<String> = []

    // UI状態
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showNewFileDialog = false
    @State private var newFileName: String = ""
    @State private var showDeleteConfirmation = false
    @State private var showImportPicker = false
    @State private var showExportPicker = false

    private var isEditing: Bool { skill != nil }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        SkillDefinition.isValidDirectoryName(directoryName) &&
        description.count <= SkillDefinition.maxDescriptionLength &&
        files["SKILL.md"] != nil
    }

    private var directoryNameValidationError: String? {
        if directoryName.isEmpty { return nil }
        if !SkillDefinition.isValidDirectoryName(directoryName) {
            return "Must be 2-64 characters: lowercase letters, numbers, hyphens only"
        }
        return nil
    }

    private var sortedFilePaths: [String] {
        // SKILL.mdを先頭に、残りはアルファベット順
        var paths = Array(files.keys) + Array(binaryFiles)
        paths.sort { lhs, rhs in
            if lhs == "SKILL.md" { return true }
            if rhs == "SKILL.md" { return false }
            return lhs < rhs
        }
        return paths
    }

    private var canDeleteSelectedFile: Bool {
        guard let selected = selectedFile else { return false }
        return selected != "SKILL.md"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            headerView

            Divider()

            // メインコンテンツ
            HSplitView {
                // 左側: 基本情報 + ファイルツリー
                leftPanel
                    .frame(minWidth: 200, maxWidth: 280)

                // 右側: ファイルエディタ
                rightPanel
                    .frame(minWidth: 400)
            }

            Divider()

            // フッター
            footerView
        }
        .frame(width: 900, height: 650)
        .onAppear { loadSkillData() }
        .sheet(isPresented: $showNewFileDialog) { newFileDialogView }
        .confirmationDialog(
            "Delete File",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelectedFile() }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let selected = selectedFile {
                Text("Are you sure you want to delete '\(selected)'?")
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .fileExporter(
            isPresented: $showExportPicker,
            document: SkillArchiveDocument(archiveData: buildArchiveData()),
            contentType: .zip,
            defaultFilename: "\(directoryName.isEmpty ? "skill" : directoryName).zip"
        ) { result in
            // エクスポート完了（エラー処理のみ）
            if case .failure(let error) = result {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
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
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // 基本情報フォーム
            Form {
                Section("Basic Information") {
                    TextField("Skill Name", text: $name)
                        .accessibilityIdentifier("SkillNameField")

                    TextField("Description", text: $description)
                        .accessibilityIdentifier("SkillDescriptionField")

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Directory Name", text: $directoryName)
                            .accessibilityIdentifier("SkillDirectoryNameField")
                            .disabled(isEditing)
                            .onChange(of: directoryName) { _, newValue in
                                let lowercased = newValue.lowercased()
                                if lowercased != newValue {
                                    directoryName = lowercased
                                }
                            }

                        if let error = directoryNameValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 200)

            Divider()

            // ファイルツリーヘッダー
            HStack {
                Text("Files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    newFileName = ""
                    showNewFileDialog = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("Add File")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain)
                .disabled(!canDeleteSelectedFile)
                .help("Delete File")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // ファイルツリー
            List(sortedFilePaths, id: \.self, selection: $selectedFile) { path in
                fileRowView(path: path)
            }
            .listStyle(.plain)

            Divider()

            // インポート/エクスポートボタン
            HStack {
                Button {
                    showImportPicker = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .help("Import ZIP archive")

                Button {
                    showExportPicker = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("Export as ZIP")
            }
            .padding()
        }
    }

    private func fileRowView(path: String) -> some View {
        HStack {
            Image(systemName: fileIcon(for: path))
                .foregroundStyle(fileIconColor(for: path))
                .frame(width: 16)

            Text(path)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if binaryFiles.contains(path) {
                Text("binary")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .background(.quaternary)
                    .cornerRadius(2)
            }

            if path == "SKILL.md" {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var rightPanel: some View {
        VStack(spacing: 0) {
            if let selected = selectedFile {
                // ファイルパスヘッダー
                HStack {
                    Image(systemName: fileIcon(for: selected))
                        .foregroundStyle(fileIconColor(for: selected))
                    Text(selected)
                        .font(.headline)
                    Spacer()
                }
                .padding()
                .background(.bar)

                Divider()

                // エディタ or バイナリ表示
                if binaryFiles.contains(selected) {
                    binaryFileView
                } else if let content = files[selected] {
                    TextEditor(text: Binding(
                        get: { content },
                        set: { files[selected] = $0 }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("SkillContentEditor")
                } else {
                    Text("File not found")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // ファイル未選択
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Select a file to edit")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // エラーメッセージ
            if let errorMessage = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Spacer()
                    Button {
                        self.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(.red.opacity(0.1))
            }
        }
    }

    private var binaryFileView: some View {
        VStack {
            Image(systemName: "doc.zipper")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Binary file (read-only)")
                .foregroundStyle(.secondary)
            Text("This file cannot be edited in the text editor.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerView: some View {
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

    private var newFileDialogView: some View {
        VStack(spacing: 16) {
            Text("New File")
                .font(.headline)

            TextField("File name (e.g., scripts/helper.py)", text: $newFileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    showNewFileDialog = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    createNewFile()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Helper Methods

    private func fileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "md": return "doc.richtext"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts": return "curlybraces"
        case "sh", "bash": return "terminal"
        case "json", "yaml", "yml": return "doc.badge.gearshape"
        case "html", "css": return "globe"
        default: return binaryFiles.contains(path) ? "doc.zipper" : "doc.text"
        }
    }

    private func fileIconColor(for path: String) -> Color {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "md": return .blue
        case "py": return .yellow
        case "js", "ts": return .orange
        case "sh", "bash": return .green
        case "json", "yaml", "yml": return .purple
        default: return .secondary
        }
    }

    private func loadSkillData() {
        if let skill = skill {
            name = skill.name
            description = skill.description
            directoryName = skill.directoryName

            // アーカイブから全ファイルを抽出
            files = container.skillArchiveService.extractAllFiles(from: skill.archiveData)

            // ファイル一覧を取得してバイナリファイルを特定
            if let entries = try? container.skillArchiveService.listFiles(archiveData: skill.archiveData) {
                for entry in entries where !entry.isDirectory {
                    if !container.skillArchiveService.isTextFile(entry.path) && files[entry.path] == nil {
                        binaryFiles.insert(entry.path)
                    }
                }
            }

            // 最初のファイルを選択
            selectedFile = "SKILL.md"
        } else {
            // 新規作成: デフォルトのSKILL.mdを設定
            files = [
                "SKILL.md": """
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
            ]
            selectedFile = "SKILL.md"
        }
    }

    private func createNewFile() {
        let trimmedName = newFileName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // 既存チェック
        if files[trimmedName] != nil || binaryFiles.contains(trimmedName) {
            errorMessage = "File already exists: \(trimmedName)"
            showNewFileDialog = false
            return
        }

        // 新規ファイル追加
        files[trimmedName] = ""
        selectedFile = trimmedName
        showNewFileDialog = false
    }

    private func deleteSelectedFile() {
        guard let selected = selectedFile, selected != "SKILL.md" else { return }

        files.removeValue(forKey: selected)
        binaryFiles.remove(selected)

        // 別のファイルを選択
        selectedFile = sortedFilePaths.first
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            do {
                // ZIPからインポート
                guard url.startAccessingSecurityScopedResource() else {
                    errorMessage = "Cannot access file"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let data = try Data(contentsOf: url)
                let imported = try container.skillArchiveService.importFromZip(
                    data: data,
                    suggestedName: url.deletingPathExtension().lastPathComponent
                )

                // ファイルを更新
                files = container.skillArchiveService.extractAllFiles(from: imported.archiveData)
                binaryFiles.removeAll()

                for entry in imported.files where !entry.isDirectory {
                    if !container.skillArchiveService.isTextFile(entry.path) && files[entry.path] == nil {
                        binaryFiles.insert(entry.path)
                    }
                }

                // メタデータを更新（新規の場合のみ）
                if !isEditing {
                    if !imported.name.isEmpty {
                        name = imported.name
                    }
                    if !imported.description.isEmpty {
                        description = imported.description
                    }
                    if directoryName.isEmpty {
                        directoryName = imported.suggestedDirectoryName
                    }
                }

                selectedFile = "SKILL.md"
                errorMessage = nil
            } catch let error as SkillArchiveError {
                errorMessage = "Import failed: \(error)"
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }

        case .failure(let error):
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func buildArchiveData() -> Data {
        container.skillArchiveService.createArchiveFromFiles(files)
    }

    private func saveSkill() {
        isSaving = true
        errorMessage = nil

        do {
            let archiveData = buildArchiveData()
            let savedSkill: SkillDefinition

            if let existingSkill = skill {
                // 更新
                var updatedSkill = try container.skillDefinitionUseCases.update(
                    id: existingSkill.id,
                    name: name,
                    description: description
                )

                // アーカイブを更新
                updatedSkill = try container.skillDefinitionUseCases.reimport(
                    id: existingSkill.id,
                    archiveData: archiveData
                )
                savedSkill = updatedSkill
            } else {
                // 新規作成
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

// MARK: - SkillArchiveDocument

/// ZIPエクスポート用のFileDocument
struct SkillArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    var archiveData: Data

    init(archiveData: Data) {
        self.archiveData = archiveData
    }

    init(configuration: ReadConfiguration) throws {
        archiveData = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: archiveData)
    }
}
