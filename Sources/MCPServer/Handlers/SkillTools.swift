// Sources/MCPServer/Handlers/SkillTools.swift
// スキル管理MCPツール

import Foundation
import Domain
import Infrastructure

// MARK: - Skill Tools

extension MCPServer {

    /// register_skill ツール: スキルをDBに登録
    /// - Parameters:
    ///   - name: スキル表示名
    ///   - description: 概要説明（任意、最大256文字）
    ///   - directoryName: ディレクトリ名（英小文字・数字・ハイフン、2-64文字）
    ///   - skillMdContent: SKILL.mdのテキスト内容（folderPathと排他）
    ///   - folderPath: ローカルフォルダパス（skillMdContentと排他）
    func registerSkill(
        name: String,
        description: String?,
        directoryName: String,
        skillMdContent: String?,
        folderPath: String?
    ) throws -> [String: Any] {
        // 1. パラメータ検証: name が空でないこと
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MCPError.validationError("name must not be empty")
        }

        // 2. directory_name のバリデーション
        guard SkillDefinition.isValidDirectoryName(directoryName) else {
            throw MCPError.validationError("directory_name is invalid: must be 2-64 characters, lowercase letters, digits, and hyphens only (e.g. 'code-review')")
        }

        // 3. 排他パラメータ検証: skill_md_content / folder_path のいずれか必須
        let hasContent = skillMdContent != nil
        let hasFolder = folderPath != nil

        if !hasContent && !hasFolder {
            throw MCPError.validationError("Either skill_md_content or folder_path must be provided")
        }
        if hasContent && hasFolder {
            throw MCPError.validationError("skill_md_content and folder_path are mutually exclusive - provide only one")
        }

        // 4. description の長さチェック
        if let desc = description, desc.count > SkillDefinition.maxDescriptionLength {
            throw MCPError.validationError("description must be \(SkillDefinition.maxDescriptionLength) characters or less (got \(desc.count))")
        }

        // 5. 重複チェック
        if let existing = try skillDefinitionRepository.findByDirectoryName(directoryName) {
            throw MCPError.validationError("directory_name '\(directoryName)' already exists (skill_id: \(existing.id.value))")
        }

        // 6. アーカイブデータ作成
        let archiveData: Data
        if let content = skillMdContent {
            archiveData = DatabaseSetup.createZipArchive(skillMdContent: content)
        } else if let path = folderPath {
            archiveData = try createZipFromFolder(path: path)
        } else {
            // ここには到達しないが安全のため
            throw MCPError.validationError("Either skill_md_content or folder_path must be provided")
        }

        // 7. エンティティ作成 + 保存
        let skillId = SkillID.generate()
        let skill = SkillDefinition(
            id: skillId,
            name: name,
            description: description ?? "",
            directoryName: directoryName,
            archiveData: archiveData
        )

        try skillDefinitionRepository.save(skill)

        Self.log("Skill registered: \(skillId.value) (\(directoryName))")

        return [
            "status": "success",
            "skill_id": skillId.value,
            "name": name,
            "directory_name": directoryName,
            "archive_size": archiveData.count
        ]
    }

    // MARK: - Private Helpers

    /// フォルダからZIPアーカイブを作成
    private func createZipFromFolder(path: String) throws -> Data {
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: path)

        // フォルダ存在チェック
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPError.validationError("folder_path does not exist or is not a directory: \(path)")
        }

        // SKILL.md存在チェック
        let skillMdPath = folderURL.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: skillMdPath.path) else {
            throw MCPError.validationError("folder_path must contain SKILL.md: \(path)")
        }

        // フォルダ内の全ファイルを収集（再帰的）
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw MCPError.validationError("Cannot enumerate folder: \(path)")
        }

        var files: [(relativePath: String, data: Data)] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")

            // 禁止パターンチェック
            let isForbidden = SkillDefinition.forbiddenPatterns.contains { pattern in
                if pattern.hasSuffix("/") {
                    return relativePath.hasPrefix(pattern) || relativePath.contains("/\(pattern)")
                } else if pattern.hasPrefix("*") {
                    let ext = String(pattern.dropFirst())
                    return relativePath.hasSuffix(ext)
                } else {
                    return relativePath == pattern || relativePath.hasSuffix("/\(pattern)")
                }
            }
            if isForbidden { continue }

            let data = try Data(contentsOf: fileURL)
            files.append((relativePath: relativePath, data: data))
        }

        // 簡易ZIPアーカイブ作成（非圧縮、複数ファイル対応）
        return createZipArchive(files: files)
    }

    /// 複数ファイルからZIPアーカイブを作成（非圧縮）
    private func createZipArchive(files: [(relativePath: String, data: Data)]) -> Data {
        var zipData = Data()
        var centralDirectory = Data()
        var fileCount: UInt16 = 0

        for file in files {
            let fileNameData = file.relativePath.data(using: .utf8)!
            let contentData = file.data
            let crc = DatabaseSetup.crc32(contentData)

            let localHeaderOffset = UInt32(zipData.count)

            // Local file header
            zipData.append(contentsOf: [0x50, 0x4b, 0x03, 0x04]) // signature
            zipData.append(contentsOf: [0x0a, 0x00]) // version needed (1.0)
            zipData.append(contentsOf: [0x00, 0x00]) // flags
            zipData.append(contentsOf: [0x00, 0x00]) // compression (stored)
            zipData.append(contentsOf: [0x00, 0x00]) // mod time
            zipData.append(contentsOf: [0x00, 0x00]) // mod date
            zipData.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            zipData.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
            zipData.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
            zipData.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) })
            zipData.append(contentsOf: [0x00, 0x00]) // extra field length
            zipData.append(fileNameData)
            zipData.append(contentData)

            // Central directory entry
            centralDirectory.append(contentsOf: [0x50, 0x4b, 0x01, 0x02]) // signature
            centralDirectory.append(contentsOf: [0x14, 0x00]) // version made by
            centralDirectory.append(contentsOf: [0x0a, 0x00]) // version needed
            centralDirectory.append(contentsOf: [0x00, 0x00]) // flags
            centralDirectory.append(contentsOf: [0x00, 0x00]) // compression
            centralDirectory.append(contentsOf: [0x00, 0x00]) // mod time
            centralDirectory.append(contentsOf: [0x00, 0x00]) // mod date
            centralDirectory.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
            centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
            centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) })
            centralDirectory.append(contentsOf: [0x00, 0x00]) // extra field length
            centralDirectory.append(contentsOf: [0x00, 0x00]) // file comment length
            centralDirectory.append(contentsOf: [0x00, 0x00]) // disk number
            centralDirectory.append(contentsOf: [0x00, 0x00]) // internal file attributes
            centralDirectory.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // external file attributes
            centralDirectory.append(contentsOf: withUnsafeBytes(of: localHeaderOffset.littleEndian) { Array($0) })
            centralDirectory.append(fileNameData)

            fileCount += 1
        }

        let centralDirOffset = UInt32(zipData.count)
        zipData.append(centralDirectory)
        let centralDirSize = UInt32(centralDirectory.count)

        // End of central directory
        zipData.append(contentsOf: [0x50, 0x4b, 0x05, 0x06]) // signature
        zipData.append(contentsOf: [0x00, 0x00]) // disk number
        zipData.append(contentsOf: [0x00, 0x00]) // disk with central dir
        zipData.append(contentsOf: withUnsafeBytes(of: fileCount.littleEndian) { Array($0) })
        zipData.append(contentsOf: withUnsafeBytes(of: fileCount.littleEndian) { Array($0) })
        zipData.append(contentsOf: withUnsafeBytes(of: centralDirSize.littleEndian) { Array($0) })
        zipData.append(contentsOf: withUnsafeBytes(of: centralDirOffset.littleEndian) { Array($0) })
        zipData.append(contentsOf: [0x00, 0x00]) // comment length

        return zipData
    }
}
