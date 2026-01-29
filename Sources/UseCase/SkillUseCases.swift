// Sources/UseCase/SkillUseCases.swift
// スキル機能 - ユースケース
// 参照: docs/design/AGENT_SKILLS.md

import Foundation
import Domain

// MARK: - SkillDefinitionUseCases

/// スキル定義管理ユースケース
public struct SkillDefinitionUseCases: Sendable {
    private let skillRepository: any SkillDefinitionRepositoryProtocol

    public init(skillRepository: any SkillDefinitionRepositoryProtocol) {
        self.skillRepository = skillRepository
    }

    /// スキル定義を取得
    public func findById(_ id: SkillID) throws -> SkillDefinition? {
        try skillRepository.findById(id)
    }

    /// 全スキル定義を取得（名前順）
    public func findAll() throws -> [SkillDefinition] {
        try skillRepository.findAll()
    }

    /// ディレクトリ名でスキル定義を検索
    public func findByDirectoryName(_ directoryName: String) throws -> SkillDefinition? {
        try skillRepository.findByDirectoryName(directoryName)
    }

    /// スキル定義を作成
    /// - Throws: `SkillError` バリデーションエラー時
    public func create(
        name: String,
        description: String,
        directoryName: String,
        content: String
    ) throws -> SkillDefinition {
        // バリデーション
        try validateSkillInput(name: name, description: description, directoryName: directoryName, content: content)

        // ディレクトリ名の重複チェック
        if let existing = try skillRepository.findByDirectoryName(directoryName) {
            throw SkillError.directoryNameAlreadyExists(directoryName, existingId: existing.id.value)
        }

        let skill = SkillDefinition(
            id: SkillID.generate(),
            name: name,
            description: description,
            directoryName: directoryName,
            content: content,
            createdAt: Date(),
            updatedAt: Date()
        )

        try skillRepository.save(skill)
        return skill
    }

    /// スキル定義を更新
    /// - Throws: `SkillError` バリデーションエラー時
    public func update(
        id: SkillID,
        name: String? = nil,
        description: String? = nil,
        directoryName: String? = nil,
        content: String? = nil
    ) throws -> SkillDefinition {
        guard var skill = try skillRepository.findById(id) else {
            throw SkillError.skillNotFound(id.value)
        }

        // 更新対象のフィールドを反映
        if let name = name { skill.name = name }
        if let description = description { skill.description = description }
        if let content = content { skill.content = content }

        // ディレクトリ名変更時は重複チェック
        if let newDirectoryName = directoryName, newDirectoryName != skill.directoryName {
            if let existing = try skillRepository.findByDirectoryName(newDirectoryName) {
                throw SkillError.directoryNameAlreadyExists(newDirectoryName, existingId: existing.id.value)
            }
            skill.directoryName = newDirectoryName
        }

        // バリデーション
        try validateSkillInput(
            name: skill.name,
            description: skill.description,
            directoryName: skill.directoryName,
            content: skill.content
        )

        skill.updatedAt = Date()
        try skillRepository.save(skill)
        return skill
    }

    /// スキル定義を削除
    /// - Throws: `SkillError.skillInUse` 使用中の場合
    public func delete(_ id: SkillID) throws {
        guard try skillRepository.findById(id) != nil else {
            throw SkillError.skillNotFound(id.value)
        }

        if try skillRepository.isInUse(id) {
            throw SkillError.skillInUse(id.value)
        }

        try skillRepository.delete(id)
    }

    /// スキルが使用中かどうかを確認
    public func isInUse(_ id: SkillID) throws -> Bool {
        try skillRepository.isInUse(id)
    }

    // MARK: - Private

    private func validateSkillInput(
        name: String,
        description: String,
        directoryName: String,
        content: String
    ) throws {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw SkillError.emptyName
        }

        if !SkillDefinition.isValidDirectoryName(directoryName) {
            throw SkillError.invalidDirectoryName(directoryName)
        }

        if description.count > SkillDefinition.maxDescriptionLength {
            throw SkillError.descriptionTooLong(description.count)
        }

        if content.utf8.count > SkillDefinition.maxContentSize {
            throw SkillError.contentTooLarge(content.utf8.count)
        }
    }
}

// MARK: - AgentSkillUseCases

/// エージェントスキル割り当てユースケース
public struct AgentSkillUseCases: Sendable {
    private let assignmentRepository: any AgentSkillAssignmentRepositoryProtocol
    private let skillRepository: any SkillDefinitionRepositoryProtocol

    public init(
        assignmentRepository: any AgentSkillAssignmentRepositoryProtocol,
        skillRepository: any SkillDefinitionRepositoryProtocol
    ) {
        self.assignmentRepository = assignmentRepository
        self.skillRepository = skillRepository
    }

    /// エージェントに割り当てられたスキルを取得
    public func getAgentSkills(_ agentId: AgentID) throws -> [SkillDefinition] {
        try assignmentRepository.findByAgentId(agentId)
    }

    /// スキルを使用しているエージェントIDを取得
    public func getAgentsUsingSkill(_ skillId: SkillID) throws -> [AgentID] {
        try assignmentRepository.findBySkillId(skillId)
    }

    /// エージェントにスキルを割り当て（全置換）
    /// - Parameters:
    ///   - agentId: エージェントID
    ///   - skillIds: 割り当てるスキルIDの配列
    /// - Throws: `SkillError.skillNotFound` 存在しないスキルIDが含まれる場合
    public func assignSkills(agentId: AgentID, skillIds: [SkillID]) throws {
        // 全てのスキルIDが存在するか確認
        for skillId in skillIds {
            guard try skillRepository.findById(skillId) != nil else {
                throw SkillError.skillNotFound(skillId.value)
            }
        }

        try assignmentRepository.assignSkills(agentId: agentId, skillIds: skillIds)
    }

    /// エージェントから全スキルを削除
    public func removeAllSkills(_ agentId: AgentID) throws {
        try assignmentRepository.removeAllSkills(agentId: agentId)
    }

    /// スキルがエージェントに割り当てられているか確認
    public func isAssigned(agentId: AgentID, skillId: SkillID) throws -> Bool {
        try assignmentRepository.isAssigned(agentId: agentId, skillId: skillId)
    }
}

// MARK: - SkillError

/// スキル関連エラー
public enum SkillError: Error, Equatable {
    case skillNotFound(String)
    case directoryNameAlreadyExists(String, existingId: String)
    case skillInUse(String)
    case emptyName
    case invalidDirectoryName(String)
    case descriptionTooLong(Int)
    case contentTooLarge(Int)
}

extension SkillError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .skillNotFound(let id):
            return "スキルが見つかりません: \(id)"
        case .directoryNameAlreadyExists(let name, let existingId):
            return "ディレクトリ名 '\(name)' は既に使用されています (ID: \(existingId))"
        case .skillInUse(let id):
            return "スキル '\(id)' は使用中のため削除できません"
        case .emptyName:
            return "スキル名は必須です"
        case .invalidDirectoryName(let name):
            return "ディレクトリ名 '\(name)' は無効です（英小文字、数字、ハイフンのみ、2-64文字）"
        case .descriptionTooLong(let count):
            return "説明が長すぎます（\(count)文字、最大256文字）"
        case .contentTooLarge(let bytes):
            return "コンテンツが大きすぎます（\(bytes)バイト、最大64KB）"
        }
    }
}
