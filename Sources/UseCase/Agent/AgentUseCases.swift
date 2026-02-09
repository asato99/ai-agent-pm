// Sources/UseCase/Agent/AgentUseCases.swift
// エージェント関連ユースケース

import Foundation
import Domain

// MARK: - GetAgentsUseCase

/// エージェント一覧取得ユースケース
/// 要件: エージェントはプロジェクト非依存
public struct GetAgentsUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol

    public init(agentRepository: any AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    public func execute() throws -> [Agent] {
        try agentRepository.findAll()
    }
}

// MARK: - CreateAgentUseCase

/// エージェント作成ユースケース
/// 要件: エージェントはプロジェクト非依存、階層構造をサポート
public struct CreateAgentUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol
    private let credentialRepository: (any AgentCredentialRepositoryProtocol)?

    public init(
        agentRepository: any AgentRepositoryProtocol,
        credentialRepository: (any AgentCredentialRepositoryProtocol)? = nil
    ) {
        self.agentRepository = agentRepository
        self.credentialRepository = credentialRepository
    }

    public func execute(
        name: String,
        role: String,
        hierarchyType: AgentHierarchyType = .worker,
        roleType: AgentRoleType = .developer,
        type: AgentType = .ai,
        aiType: AIType? = nil,
        parentAgentId: AgentID? = nil,
        maxParallelTasks: Int = 1,
        systemPrompt: String? = nil,
        kickMethod: KickMethod = .cli,
        authLevel: AuthLevel = .level0,
        passkey: String? = nil
    ) throws -> Agent {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.validationFailed("Name cannot be empty")
        }

        let agent = Agent(
            id: AgentID.generate(),
            name: name,
            role: role,
            type: type,
            aiType: aiType,
            hierarchyType: hierarchyType,
            roleType: roleType,
            parentAgentId: parentAgentId,
            maxParallelTasks: maxParallelTasks,
            systemPrompt: systemPrompt,
            kickMethod: kickMethod,
            authLevel: authLevel,
            passkey: passkey
        )

        try agentRepository.save(agent)

        // パスキーが設定されている場合はAgentCredentialも作成
        if let passkey = passkey, !passkey.isEmpty, let credentialRepo = credentialRepository {
            let credential = AgentCredential(agentId: agent.id, rawPasskey: passkey)
            try credentialRepo.save(credential)
        }

        return agent
    }
}

// MARK: - GetAgentProfileUseCase

/// エージェントプロファイル取得ユースケース
public struct GetAgentProfileUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol

    public init(agentRepository: any AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    public func execute(agentId: AgentID) throws -> Agent {
        guard let agent = try agentRepository.findById(agentId) else {
            throw UseCaseError.agentNotFound(agentId)
        }
        return agent
    }
}

// MARK: - GetAgentSessionsUseCase

/// エージェントのセッション履歴取得ユースケース
public struct GetAgentSessionsUseCase: Sendable {
    private let sessionRepository: any SessionRepositoryProtocol

    public init(sessionRepository: any SessionRepositoryProtocol) {
        self.sessionRepository = sessionRepository
    }

    public func execute(agentId: AgentID) throws -> [Session] {
        try sessionRepository.findByAgent(agentId)
    }
}

// MARK: - Phase 3.1: Managed Agents UseCase

/// 管轄AIエージェント取得ユースケース
/// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ3.1
///
/// humanエージェントを起点として、その配下のAIエージェントのみを取得する。
/// humanエージェントの配下に別のhumanエージェントがいる場合、そこで区切る。
///
/// 例: human-A → ai-1, ai-2, human-B → ai-3
/// - human-Aの管轄: [ai-1, ai-2]（human-Bとai-3は含まない）
/// - human-Bの管轄: [ai-3]
public struct GetManagedAgentsUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol

    public init(agentRepository: any AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    /// 指定したhumanエージェントの管轄下にあるAIエージェントを取得
    /// - Parameter rootAgentId: 起点となるhumanエージェントのID
    /// - Returns: 管轄下のAIエージェント一覧
    /// - Throws: rootMustBeHuman - 起点エージェントがhumanでない場合
    public func execute(rootAgentId: AgentID) throws -> [Agent] {
        guard let rootAgent = try agentRepository.findById(rootAgentId) else {
            throw UseCaseError.agentNotFound(rootAgentId)
        }

        guard rootAgent.type == .human else {
            throw UseCaseError.validationFailed("Root agent must be of type human")
        }

        var result: [Agent] = []
        try traverse(rootAgentId, into: &result)
        return result
    }

    /// 再帰的に配下のエージェントを走査
    /// humanエージェントに到達したらそこで区切る（その配下は含めない）
    private func traverse(_ agentId: AgentID, into result: inout [Agent]) throws {
        let children = try agentRepository.findByParent(agentId)

        for child in children {
            if child.type == .human {
                // humanエージェントで区切り（そのエージェントもその配下も含めない）
                continue
            }

            // AIエージェントは結果に追加
            result.append(child)

            // さらにその配下も走査
            try traverse(child.id, into: &result)
        }
    }
}
