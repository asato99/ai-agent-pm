// Sources/MCPServer/Handlers/SkillTools.swift
// スキル管理MCPツール

import Foundation
import Domain
import UseCase

// MARK: - Skill Tools

extension MCPServer {

    /// register_skill ツール: スキルをDBに登録
    ///
    /// 3つの入力ソース（排他）:
    /// - zip_file_path: ZIPファイルのパス
    /// - folder_path: ローカルフォルダのパス
    /// - skill_md_content: SKILL.mdのテキスト内容
    ///
    /// name / description / directory_name は frontmatter から自動抽出されるが、
    /// 引数で明示的に指定した場合はオーバーライドされる。
    func registerSkill(
        zipFilePath: String?,
        folderPath: String?,
        skillMdContent: String?,
        name: String?,
        description: String?,
        directoryName: String?
    ) throws -> [String: Any] {
        // 1. 入力ソースの排他チェック
        let sources = [zipFilePath != nil, folderPath != nil, skillMdContent != nil]
        let sourceCount = sources.filter { $0 }.count

        if sourceCount == 0 {
            throw MCPError.validationError(
                "One of zip_file_path, folder_path, or skill_md_content must be provided"
            )
        }
        if sourceCount > 1 {
            throw MCPError.validationError(
                "zip_file_path, folder_path, and skill_md_content are mutually exclusive - provide only one"
            )
        }

        // 2. SkillArchiveService 経由でインポート
        let imported: ImportedSkill

        if let zipPath = zipFilePath {
            let url = URL(fileURLWithPath: zipPath)
            guard FileManager.default.fileExists(atPath: zipPath) else {
                throw MCPError.validationError("zip_file_path does not exist: \(zipPath)")
            }
            let data = try Data(contentsOf: url)
            let suggestedName = url.deletingPathExtension().lastPathComponent
            imported = try skillArchiveService.importFromZip(data: data, suggestedName: suggestedName)

        } else if let path = folderPath {
            let url = URL(fileURLWithPath: path)
            imported = try skillArchiveService.importFromFolder(url: url)

        } else if let content = skillMdContent {
            let archiveData = skillArchiveService.createArchiveFromContent(content)
            imported = try skillArchiveService.importFromZip(data: archiveData, suggestedName: "skill")

        } else {
            // ここには到達しないが安全のため
            throw MCPError.validationError(
                "One of zip_file_path, folder_path, or skill_md_content must be provided"
            )
        }

        // 3. name / description / directoryName を決定（引数オーバーライド優先）
        let finalName = name ?? imported.name
        let finalDescription = description ?? imported.description
        let finalDirectoryName = directoryName ?? imported.suggestedDirectoryName

        // 4. SkillDefinitionUseCases 経由で永続化
        let skill = try skillDefinitionUseCases.create(
            name: finalName,
            description: finalDescription,
            directoryName: finalDirectoryName,
            archiveData: imported.archiveData
        )

        Self.log("Skill registered: \(skill.id.value) (\(skill.directoryName))")

        return [
            "status": "success",
            "skill_id": skill.id.value,
            "name": skill.name,
            "directory_name": skill.directoryName,
            "archive_size": skill.archiveData.count
        ]
    }
}
