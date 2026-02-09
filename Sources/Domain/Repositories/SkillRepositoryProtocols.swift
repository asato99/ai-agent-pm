// Sources/Domain/Repositories/SkillRepositoryProtocols.swift
// スキル関連のリポジトリプロトコル（SkillDefinition, AgentSkillAssignment）
// 参照: docs/design/AGENT_SKILLS.md

import Foundation

// MARK: - SkillDefinitionRepositoryProtocol

/// スキル定義リポジトリのプロトコル
public protocol SkillDefinitionRepositoryProtocol: Sendable {
    /// 全スキル定義を取得
    func findAll() throws -> [SkillDefinition]

    /// IDでスキル定義を検索
    func findById(_ id: SkillID) throws -> SkillDefinition?

    /// ディレクトリ名でスキル定義を検索
    func findByDirectoryName(_ directoryName: String) throws -> SkillDefinition?

    /// スキル定義を保存（作成または更新）
    func save(_ skill: SkillDefinition) throws

    /// スキル定義を削除
    func delete(_ id: SkillID) throws

    /// スキル定義が使用中か確認（エージェントに割り当てられているか）
    func isInUse(_ id: SkillID) throws -> Bool
}

// MARK: - AgentSkillAssignmentRepositoryProtocol

/// エージェントスキル割り当てリポジトリのプロトコル
public protocol AgentSkillAssignmentRepositoryProtocol: Sendable {
    /// エージェントに割り当てられたスキル定義一覧を取得
    func findByAgentId(_ agentId: AgentID) throws -> [SkillDefinition]

    /// スキルが割り当てられたエージェント一覧を取得
    func findBySkillId(_ skillId: SkillID) throws -> [AgentID]

    /// エージェントにスキルを割り当て（全置換）
    /// 既存の割り当てを全て削除し、新しい割り当てを作成
    func assignSkills(agentId: AgentID, skillIds: [SkillID]) throws

    /// エージェントの全スキル割り当てを削除
    func removeAllSkills(agentId: AgentID) throws

    /// 特定のスキル割り当てが存在するか確認
    func isAssigned(agentId: AgentID, skillId: SkillID) throws -> Bool
}
