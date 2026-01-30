// Sources/App/Services/SkillArchiveService.swift
// 参照: docs/design/AGENT_SKILLS.md - スキルアーカイブ管理

import Foundation
import Domain
import Compression

// MARK: - ImportedSkill

/// インポート結果
public struct ImportedSkill {
    /// SKILL.mdのfrontmatterから抽出された名前
    public let name: String
    /// SKILL.mdのfrontmatterから抽出された概要
    public let description: String
    /// 推奨ディレクトリ名（フォルダ名/ZIP名）
    public let suggestedDirectoryName: String
    /// ZIPアーカイブデータ
    public let archiveData: Data
    /// アーカイブ内のファイル一覧
    public let files: [SkillFileEntry]

    public init(
        name: String,
        description: String,
        suggestedDirectoryName: String,
        archiveData: Data,
        files: [SkillFileEntry]
    ) {
        self.name = name
        self.description = description
        self.suggestedDirectoryName = suggestedDirectoryName
        self.archiveData = archiveData
        self.files = files
    }
}

// MARK: - SkillArchiveError

/// スキルアーカイブ関連エラー
public enum SkillArchiveError: Error, Equatable {
    case invalidZipFormat
    case missingSkillMd
    case archiveTooLarge(Int)
    case forbiddenFile(String)
    case extractionFailed(String)
    case frontmatterParseError
}

// MARK: - SkillArchiveService

/// スキルアーカイブを処理するサービス
public final class SkillArchiveService: @unchecked Sendable {

    public init() {}

    // MARK: - Import

    /// ZIPアーカイブからスキルをインポート
    public func importFromZip(data: Data, suggestedName: String) throws -> ImportedSkill {
        // サイズチェック
        if data.count > SkillDefinition.maxArchiveSize {
            throw SkillArchiveError.archiveTooLarge(data.count)
        }

        // ZIPを解析してファイル一覧を取得
        var files = try listFiles(archiveData: data)

        // SKILL.mdの存在確認
        guard files.contains(where: { $0.path == "SKILL.md" || $0.path.hasSuffix("/SKILL.md") }) else {
            throw SkillArchiveError.missingSkillMd
        }

        // トップレベルディレクトリの検出と除去
        // Finderで圧縮すると「folder/SKILL.md」のような構成になるため
        let rootPrefix = detectCommonRootDirectory(files: files)
        var processedData = data
        var processedFiles = files

        if let prefix = rootPrefix {
            // ルートディレクトリを除去してZIPを再構築
            let allContents = extractAllFiles(from: data)
            var normalizedContents: [String: String] = [:]

            for (path, content) in allContents {
                if path.hasPrefix(prefix) {
                    let newPath = String(path.dropFirst(prefix.count))
                    if !newPath.isEmpty {
                        normalizedContents[newPath] = content
                    }
                }
            }

            processedData = createArchiveFromFiles(normalizedContents)
            processedFiles = normalizedContents.map { path, content in
                SkillFileEntry(
                    path: path,
                    isDirectory: path.hasSuffix("/"),
                    size: Int64(content.utf8.count)
                )
            }.sorted { $0.path < $1.path }
        }

        // 禁止ファイルのチェック
        for file in processedFiles {
            if isForbiddenPath(file.path) {
                throw SkillArchiveError.forbiddenFile(file.path)
            }
        }

        // SKILL.mdの内容を抽出してfrontmatterをパース
        let (name, description) = try parseSkillMdFrontmatter(from: processedData)

        // ディレクトリ名を正規化
        let directoryName = normalizeDirectoryName(suggestedName)

        return ImportedSkill(
            name: name.isEmpty ? suggestedName : name,
            description: description,
            suggestedDirectoryName: directoryName,
            archiveData: processedData,
            files: processedFiles
        )
    }

    /// 共通のルートディレクトリを検出（例: "my-skill/" が全ファイルの共通プレフィックスの場合）
    private func detectCommonRootDirectory(files: [SkillFileEntry]) -> String? {
        // ファイルのみを対象にする（ディレクトリエントリは除く）
        let filePaths = files.filter { !$0.isDirectory }.map { $0.path }

        guard !filePaths.isEmpty else { return nil }

        // 最初のファイルのパスからルートディレクトリ候補を取得
        guard let firstPath = filePaths.first,
              let slashIndex = firstPath.firstIndex(of: "/") else {
            return nil
        }

        let rootCandidate = String(firstPath[...slashIndex])  // "folder/" を含む

        // 全てのファイルがこのプレフィックスを持っているか確認
        let allHavePrefix = filePaths.allSatisfy { $0.hasPrefix(rootCandidate) }

        if allHavePrefix {
            return rootCandidate
        }

        return nil
    }

    /// フォルダからスキルをインポート（ZIPに変換）
    public func importFromFolder(url: URL) throws -> ImportedSkill {
        let fileManager = FileManager.default
        let folderName = url.lastPathComponent

        // フォルダ内のSKILL.mdを確認
        let skillMdPath = url.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: skillMdPath.path) else {
            throw SkillArchiveError.missingSkillMd
        }

        // ZIPアーカイブを作成
        let archiveData = try createZipFromFolder(url: url)

        // サイズチェック
        if archiveData.count > SkillDefinition.maxArchiveSize {
            throw SkillArchiveError.archiveTooLarge(archiveData.count)
        }

        return try importFromZip(data: archiveData, suggestedName: folderName)
    }

    // MARK: - Export

    /// スキルをZIPとしてエクスポート
    public func exportToZip(skill: SkillDefinition) -> Data {
        skill.archiveData
    }

    // MARK: - Content Access

    /// アーカイブからSKILL.mdの内容を取得
    public func getSkillMdContent(from archiveData: Data) -> String? {
        extractSkillMdContent(from: archiveData)
    }

    /// SKILL.md内容からZIPアーカイブを作成
    /// 簡易的なZIPアーカイブ（SKILL.mdのみを含む）を作成
    public func createArchiveFromContent(_ content: String) -> Data {
        let contentData = content.data(using: .utf8) ?? Data()
        let fileName = "SKILL.md"
        let fileNameData = fileName.data(using: .utf8)!
        let crc = crc32(contentData)

        var data = Data()

        // Local File Header
        data.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
        data.append(contentsOf: [0x0a, 0x00]) // version
        data.append(contentsOf: [0x00, 0x00]) // flags
        data.append(contentsOf: [0x00, 0x00]) // compression (stored)
        data.append(contentsOf: [0x00, 0x00]) // mod time
        data.append(contentsOf: [0x00, 0x00]) // mod date
        data.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x00]) // extra field length
        data.append(fileNameData)
        data.append(contentData)

        let localHeaderOffset = 0

        // Central Directory Entry
        var centralDirectory = Data()
        centralDirectory.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
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
        centralDirectory.append(contentsOf: [0x00, 0x00]) // internal attrs
        centralDirectory.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // external attrs
        centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt32(localHeaderOffset).littleEndian) { Array($0) })
        centralDirectory.append(fileNameData)

        let centralDirOffset = data.count
        data.append(centralDirectory)

        // End of Central Directory
        data.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
        data.append(contentsOf: [0x00, 0x00]) // disk number
        data.append(contentsOf: [0x00, 0x00]) // disk with central dir
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // entry count
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // total entries
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirectory.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirOffset).littleEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x00]) // comment length

        return data
    }

    // MARK: - File Listing

    /// アーカイブ内のファイル一覧を取得
    public func listFiles(archiveData: Data) throws -> [SkillFileEntry] {
        var entries: [SkillFileEntry] = []

        // ZIPのEnd of Central Directoryを探す
        guard archiveData.count >= 22 else {
            throw SkillArchiveError.invalidZipFormat
        }

        // EOCDを逆方向に検索
        var eocdOffset = -1
        for i in stride(from: archiveData.count - 22, through: max(0, archiveData.count - 65557), by: -1) {
            if archiveData[i] == 0x50 && archiveData[i+1] == 0x4b &&
               archiveData[i+2] == 0x05 && archiveData[i+3] == 0x06 {
                eocdOffset = i
                break
            }
        }

        guard eocdOffset >= 0 else {
            throw SkillArchiveError.invalidZipFormat
        }

        // Central Directoryの位置とエントリ数を取得
        let centralDirOffset = Int(readUInt32(from: archiveData, at: eocdOffset + 16))
        let entryCount = Int(readUInt16(from: archiveData, at: eocdOffset + 10))

        // Central Directoryを解析
        var offset = centralDirOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= archiveData.count else { break }

            // Central Directory File Header シグネチャ確認
            guard archiveData[offset] == 0x50 && archiveData[offset+1] == 0x4b &&
                  archiveData[offset+2] == 0x01 && archiveData[offset+3] == 0x02 else {
                break
            }

            let fileNameLength = Int(readUInt16(from: archiveData, at: offset + 28))
            let extraFieldLength = Int(readUInt16(from: archiveData, at: offset + 30))
            let fileCommentLength = Int(readUInt16(from: archiveData, at: offset + 32))
            let uncompressedSize = Int64(readUInt32(from: archiveData, at: offset + 24))

            // ファイル名を取得
            let fileNameStart = offset + 46
            let fileNameEnd = fileNameStart + fileNameLength
            guard fileNameEnd <= archiveData.count else { break }

            if let fileName = String(data: archiveData[fileNameStart..<fileNameEnd], encoding: .utf8) {
                let isDirectory = fileName.hasSuffix("/")
                entries.append(SkillFileEntry(
                    path: fileName,
                    isDirectory: isDirectory,
                    size: uncompressedSize
                ))
            }

            offset = fileNameEnd + extraFieldLength + fileCommentLength
        }

        return entries.sorted { $0.path < $1.path }
    }

    // MARK: - Private Methods

    /// ディレクトリ名を正規化（英小文字、数字、ハイフンのみ）
    private func normalizeDirectoryName(_ name: String) -> String {
        // 拡張子を除去
        var normalized = name.replacingOccurrences(of: ".zip", with: "", options: .caseInsensitive)

        // 小文字に変換
        normalized = normalized.lowercased()

        // 許可されない文字をハイフンに置換
        normalized = normalized.replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)

        // 連続するハイフンを1つに
        normalized = normalized.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)

        // 先頭・末尾のハイフンを除去
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // 最小2文字を確保
        if normalized.count < 2 {
            normalized = "skill-\(normalized)"
        }

        // 最大64文字に制限
        if normalized.count > 64 {
            normalized = String(normalized.prefix(64))
        }

        return normalized
    }

    /// 禁止パスかどうかを判定
    private func isForbiddenPath(_ path: String) -> Bool {
        for pattern in SkillDefinition.forbiddenPatterns {
            if pattern.hasSuffix("/") {
                // ディレクトリパターン
                if path.hasPrefix(pattern) || path.contains("/\(pattern)") {
                    return true
                }
            } else if pattern.hasPrefix("*") {
                // ワイルドカードパターン
                let suffix = String(pattern.dropFirst())
                if path.hasSuffix(suffix) {
                    return true
                }
            } else {
                // 完全一致または部分一致
                if path == pattern || path.hasSuffix("/\(pattern)") {
                    return true
                }
            }
        }
        return false
    }

    /// SKILL.mdからfrontmatterをパース
    private func parseSkillMdFrontmatter(from archiveData: Data) throws -> (name: String, description: String) {
        // SKILL.mdを展開して取得
        guard let content = extractSkillMdContent(from: archiveData) else {
            throw SkillArchiveError.frontmatterParseError
        }

        var name = ""
        var description = ""

        // frontmatter (---で囲まれた部分) をパース
        let lines = content.components(separatedBy: .newlines)
        var inFrontmatter = false
        var frontmatterLines: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                if !inFrontmatter {
                    inFrontmatter = true
                } else {
                    break
                }
            } else if inFrontmatter {
                frontmatterLines.append(line)
            }
        }

        // YAMLライクなパース（簡易）
        for line in frontmatterLines {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespaces)

                switch key {
                case "name":
                    name = value
                case "description":
                    // 最大長で切り詰め
                    if value.count > SkillDefinition.maxDescriptionLength {
                        description = String(value.prefix(SkillDefinition.maxDescriptionLength))
                    } else {
                        description = value
                    }
                default:
                    break
                }
            }
        }

        return (name, description)
    }

    /// ZIPからSKILL.mdの内容を抽出
    private func extractSkillMdContent(from archiveData: Data) -> String? {
        // Local File Headerを検索してSKILL.mdを見つける
        var offset = 0
        while offset + 30 < archiveData.count {
            // Local File Header シグネチャ確認
            guard archiveData[offset] == 0x50 && archiveData[offset+1] == 0x4b &&
                  archiveData[offset+2] == 0x03 && archiveData[offset+3] == 0x04 else {
                break
            }

            let compressionMethod = readUInt16(from: archiveData, at: offset + 8)
            let compressedSize = Int(readUInt32(from: archiveData, at: offset + 18))
            let uncompressedSize = Int(readUInt32(from: archiveData, at: offset + 22))
            let fileNameLength = Int(readUInt16(from: archiveData, at: offset + 26))
            let extraFieldLength = Int(readUInt16(from: archiveData, at: offset + 28))

            let fileNameStart = offset + 30
            let fileNameEnd = fileNameStart + fileNameLength
            guard fileNameEnd <= archiveData.count else { break }

            if let fileName = String(data: archiveData[fileNameStart..<fileNameEnd], encoding: .utf8) {
                if fileName == "SKILL.md" || fileName.hasSuffix("/SKILL.md") {
                    let dataStart = fileNameEnd + extraFieldLength
                    let dataEnd = dataStart + compressedSize
                    guard dataEnd <= archiveData.count else { break }

                    let compressedData = Data(archiveData[dataStart..<dataEnd])

                    if compressionMethod == 0 {
                        // 非圧縮（Stored）
                        return String(data: compressedData, encoding: .utf8)
                    } else if compressionMethod == 8 {
                        // Deflate圧縮
                        if let decompressed = decompressDeflate(compressedData, expectedSize: uncompressedSize) {
                            return String(data: decompressed, encoding: .utf8)
                        }
                    }
                    return nil
                }
            }

            // 次のエントリへ
            let dataStart = fileNameEnd + extraFieldLength
            let size = compressionMethod == 0 ? uncompressedSize : compressedSize
            offset = dataStart + size
        }

        return nil
    }

    /// フォルダからZIPアーカイブを作成
    private func createZipFromFolder(url: URL) throws -> Data {
        let fileManager = FileManager.default
        var data = Data()

        // ファイル情報を収集
        var fileInfos: [(relativePath: String, content: Data, isDirectory: Bool)] = []

        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")

            // 禁止パスのスキップ
            if isForbiddenPath(relativePath) {
                enumerator?.skipDescendants()
                continue
            }

            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)

            if isDirectory.boolValue {
                fileInfos.append((relativePath: relativePath + "/", content: Data(), isDirectory: true))
            } else {
                if let content = fileManager.contents(atPath: fileURL.path) {
                    fileInfos.append((relativePath: relativePath, content: content, isDirectory: false))
                }
            }
        }

        // ローカルファイルヘッダと中央ディレクトリ情報を収集
        var centralDirectory = Data()
        var localHeaderOffsets: [Int] = []

        for fileInfo in fileInfos {
            localHeaderOffsets.append(data.count)

            let fileNameData = fileInfo.relativePath.data(using: .utf8)!
            let contentData = fileInfo.content
            let crc = fileInfo.isDirectory ? UInt32(0) : crc32(contentData)

            // Local File Header
            data.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
            data.append(contentsOf: [0x0a, 0x00]) // version
            data.append(contentsOf: [0x00, 0x00]) // flags
            data.append(contentsOf: [0x00, 0x00]) // compression (stored)
            data.append(contentsOf: [0x00, 0x00]) // mod time
            data.append(contentsOf: [0x00, 0x00]) // mod date
            data.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) })
            data.append(contentsOf: [0x00, 0x00]) // extra field length
            data.append(fileNameData)
            data.append(contentData)

            // Central Directory Entry
            centralDirectory.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
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
            centralDirectory.append(contentsOf: [0x00, 0x00]) // internal attrs
            centralDirectory.append(contentsOf: fileInfo.isDirectory
                ? [0x10, 0x00, 0x00, 0x00]  // directory attribute
                : [0x00, 0x00, 0x00, 0x00]) // file attribute
            centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt32(localHeaderOffsets.last!).littleEndian) { Array($0) })
            centralDirectory.append(fileNameData)
        }

        let centralDirOffset = data.count
        data.append(centralDirectory)

        // End of Central Directory
        data.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
        data.append(contentsOf: [0x00, 0x00]) // disk number
        data.append(contentsOf: [0x00, 0x00]) // disk with central dir
        data.append(contentsOf: withUnsafeBytes(of: UInt16(fileInfos.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(fileInfos.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirectory.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirOffset).littleEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x00]) // comment length

        return data
    }

    // MARK: - Multi-File Operations

    /// アーカイブから指定ファイルの内容を取得
    public func extractFileContent(from archiveData: Data, path: String) -> String? {
        extractFileData(from: archiveData, path: path)
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    /// アーカイブから全ファイルを抽出（パス -> 内容）
    public func extractAllFiles(from archiveData: Data) -> [String: String] {
        var result: [String: String] = [:]

        var offset = 0
        while offset + 30 < archiveData.count {
            guard archiveData[offset] == 0x50 && archiveData[offset+1] == 0x4b &&
                  archiveData[offset+2] == 0x03 && archiveData[offset+3] == 0x04 else {
                break
            }

            let compressionMethod = readUInt16(from: archiveData, at: offset + 8)
            let compressedSize = Int(readUInt32(from: archiveData, at: offset + 18))
            let uncompressedSize = Int(readUInt32(from: archiveData, at: offset + 22))
            let fileNameLength = Int(readUInt16(from: archiveData, at: offset + 26))
            let extraFieldLength = Int(readUInt16(from: archiveData, at: offset + 28))

            let fileNameStart = offset + 30
            let fileNameEnd = fileNameStart + fileNameLength
            guard fileNameEnd <= archiveData.count else { break }

            if let fileName = String(data: archiveData[fileNameStart..<fileNameEnd], encoding: .utf8) {
                let dataStart = fileNameEnd + extraFieldLength
                let dataEnd = dataStart + compressedSize
                guard dataEnd <= archiveData.count else { break }

                // ディレクトリはスキップ
                if !fileName.hasSuffix("/") {
                    let compressedContent = Data(archiveData[dataStart..<dataEnd])

                    if compressionMethod == 0 {
                        // 非圧縮
                        if let content = String(data: compressedContent, encoding: .utf8) {
                            result[fileName] = content
                        }
                    } else if compressionMethod == 8 {
                        // Deflate圧縮
                        if let decompressed = decompressDeflate(compressedContent, expectedSize: uncompressedSize),
                           let content = String(data: decompressed, encoding: .utf8) {
                            result[fileName] = content
                        }
                    }
                }

                offset = dataEnd
            } else {
                break
            }
        }

        return result
    }

    /// ファイル辞書からZIPアーカイブを作成
    public func createArchiveFromFiles(_ files: [String: String]) -> Data {
        var data = Data()
        var centralDirectory = Data()
        var localHeaderOffsets: [Int] = []

        // ファイルをソートして処理（SKILL.mdを先頭に）
        let sortedFiles = files.sorted { lhs, rhs in
            if lhs.key == "SKILL.md" { return true }
            if rhs.key == "SKILL.md" { return false }
            return lhs.key < rhs.key
        }

        for (path, content) in sortedFiles {
            localHeaderOffsets.append(data.count)

            let fileNameData = path.data(using: .utf8)!
            let contentData = content.data(using: .utf8) ?? Data()
            let crc = crc32(contentData)

            // Local File Header
            data.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
            data.append(contentsOf: [0x0a, 0x00]) // version
            data.append(contentsOf: [0x00, 0x00]) // flags
            data.append(contentsOf: [0x00, 0x00]) // compression (stored)
            data.append(contentsOf: [0x00, 0x00]) // mod time
            data.append(contentsOf: [0x00, 0x00]) // mod date
            data.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) })
            data.append(contentsOf: [0x00, 0x00]) // extra field length
            data.append(fileNameData)
            data.append(contentData)

            // Central Directory Entry
            centralDirectory.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
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
            centralDirectory.append(contentsOf: [0x00, 0x00]) // internal attrs
            centralDirectory.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // external attrs
            centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt32(localHeaderOffsets.last!).littleEndian) { Array($0) })
            centralDirectory.append(fileNameData)
        }

        let centralDirOffset = data.count
        data.append(centralDirectory)

        // End of Central Directory
        data.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
        data.append(contentsOf: [0x00, 0x00]) // disk number
        data.append(contentsOf: [0x00, 0x00]) // disk with central dir
        data.append(contentsOf: withUnsafeBytes(of: UInt16(files.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(files.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirectory.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirOffset).littleEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x00]) // comment length

        return data
    }

    /// ファイルがテキストファイルかどうかを判定
    public func isTextFile(_ path: String) -> Bool {
        let textExtensions = ["md", "txt", "py", "js", "ts", "json", "yaml", "yml", "sh", "bash",
                              "html", "css", "xml", "csv", "swift", "rs", "go", "rb", "pl"]
        let ext = (path as NSString).pathExtension.lowercased()
        return textExtensions.contains(ext) || ext.isEmpty
    }

    // MARK: - Private Helpers

    /// アーカイブからファイルデータを抽出
    private func extractFileData(from archiveData: Data, path: String) -> Data? {
        var offset = 0
        while offset + 30 < archiveData.count {
            guard archiveData[offset] == 0x50 && archiveData[offset+1] == 0x4b &&
                  archiveData[offset+2] == 0x03 && archiveData[offset+3] == 0x04 else {
                break
            }

            let compressionMethod = readUInt16(from: archiveData, at: offset + 8)
            let compressedSize = Int(readUInt32(from: archiveData, at: offset + 18))
            let uncompressedSize = Int(readUInt32(from: archiveData, at: offset + 22))
            let fileNameLength = Int(readUInt16(from: archiveData, at: offset + 26))
            let extraFieldLength = Int(readUInt16(from: archiveData, at: offset + 28))

            let fileNameStart = offset + 30
            let fileNameEnd = fileNameStart + fileNameLength
            guard fileNameEnd <= archiveData.count else { break }

            if let fileName = String(data: archiveData[fileNameStart..<fileNameEnd], encoding: .utf8) {
                let dataStart = fileNameEnd + extraFieldLength
                let dataEnd = dataStart + compressedSize
                guard dataEnd <= archiveData.count else { break }

                if fileName == path {
                    let compressedContent = Data(archiveData[dataStart..<dataEnd])

                    if compressionMethod == 0 {
                        // 非圧縮
                        return compressedContent
                    } else if compressionMethod == 8 {
                        // Deflate圧縮
                        return decompressDeflate(compressedContent, expectedSize: uncompressedSize)
                    }
                    return nil
                }

                offset = dataEnd
            } else {
                break
            }
        }
        return nil
    }

    /// CRC-32を計算
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    private func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
    }

    /// Deflate圧縮データを解凍
    private func decompressDeflate(_ compressedData: Data, expectedSize: Int) -> Data? {
        // ZIPのDeflateはraw deflate
        // compression_decode_bufferを使用（COMPRESSION_ZLIBはraw deflateも処理可能）
        let destinationBufferSize = max(expectedSize, compressedData.count * 4)
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

        let decompressedSize = compressedData.withUnsafeBytes { sourcePointer -> Int in
            guard let sourceBaseAddress = sourcePointer.baseAddress else { return 0 }
            return compression_decode_buffer(
                &destinationBuffer,
                destinationBufferSize,
                sourceBaseAddress.assumingMemoryBound(to: UInt8.self),
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else { return nil }
        return Data(destinationBuffer.prefix(decompressedSize))
    }
}
