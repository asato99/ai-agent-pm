// Sources/Domain/Entities/SkillDefinition.swift
// 参照: docs/design/AGENT_SKILLS.md - スキル定義エンティティ

import Foundation

// MARK: - SkillID

/// スキル定義のID
public struct SkillID: Hashable, Codable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    /// 新規ID生成
    public static func generate() -> SkillID {
        SkillID(value: "skl_\(UUID().uuidString.lowercased().prefix(8))")
    }
}

// MARK: - SkillDefinition

/// スキル定義エンティティ
/// アプリ側でマスタ管理するスキルの定義
/// 参照: docs/design/AGENT_SKILLS.md - Section 3.1
public struct SkillDefinition: Identifiable, Equatable, Sendable {
    public let id: SkillID
    /// 表示名（例：「コードレビュー」）
    public var name: String
    /// 概要説明（人間向け、例：「コードの品質をレビューする」）
    public var description: String
    /// ディレクトリ名（例：「code-review」）
    /// 制約: 英小文字、数字、ハイフンのみ、最大64文字
    public var directoryName: String
    /// SKILL.md の全内容（frontmatter含む）
    public var content: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: SkillID,
        name: String,
        description: String,
        directoryName: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.directoryName = directoryName
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Validation

extension SkillDefinition {
    /// directoryName のバリデーション
    /// 制約: 英小文字、数字、ハイフンのみ、2文字以上64文字以下
    /// 正規表現: ^[a-z0-9][a-z0-9-]*[a-z0-9]$
    public static func isValidDirectoryName(_ name: String) -> Bool {
        guard name.count >= 2, name.count <= 64 else { return false }
        let pattern = "^[a-z0-9][a-z0-9-]*[a-z0-9]$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    /// description の最大文字数
    public static let maxDescriptionLength = 256

    /// content の最大サイズ（バイト）
    public static let maxContentSize = 64 * 1024  // 64KB

    /// バリデーション結果
    public enum ValidationError: Error, Equatable {
        case emptyName
        case invalidDirectoryName(String)
        case descriptionTooLong(Int)
        case contentTooLarge(Int)
    }

    /// エンティティのバリデーション
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []

        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyName)
        }

        if !Self.isValidDirectoryName(directoryName) {
            errors.append(.invalidDirectoryName(directoryName))
        }

        if description.count > Self.maxDescriptionLength {
            errors.append(.descriptionTooLong(description.count))
        }

        if content.utf8.count > Self.maxContentSize {
            errors.append(.contentTooLarge(content.utf8.count))
        }

        return errors
    }

    /// バリデーションが成功するか
    public var isValid: Bool {
        validate().isEmpty
    }
}
