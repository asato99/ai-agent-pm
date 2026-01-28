// Sources/UseCase/AuthenticationUseCases.swift
// 認証関連のユースケース (Phase 3-1)
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md

import Foundation
import Domain

// MARK: - AuthenticateResult

/// 認証結果
/// 参照: docs/plan/MULTI_AGENT_USE_CASES.md - 認証フロー
public struct AuthenticateResult: Sendable {
    public let success: Bool
    public let sessionToken: String?
    public let expiresIn: Int?  // 秒数
    public let agentName: String?
    public let systemPrompt: String?  // エージェントの役割を定義するプロンプト
    public let error: String?

    public static func success(token: String, expiresIn: Int, agentName: String, systemPrompt: String?) -> AuthenticateResult {
        AuthenticateResult(
            success: true,
            sessionToken: token,
            expiresIn: expiresIn,
            agentName: agentName,
            systemPrompt: systemPrompt,
            error: nil
        )
    }

    public static func failure(error: String) -> AuthenticateResult {
        AuthenticateResult(
            success: false,
            sessionToken: nil,
            expiresIn: nil,
            agentName: nil,
            systemPrompt: nil,
            error: error
        )
    }
}

// MARK: - AuthenticateUseCase

/// エージェント認証ユースケース
/// Chat機能対応: pending_agent_purposesから起動理由を取得してセッションに設定
public struct AuthenticateUseCase: Sendable {
    private let credentialRepository: any AgentCredentialRepositoryProtocol
    private let sessionRepository: any AgentSessionRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let pendingPurposeRepository: (any PendingAgentPurposeRepositoryProtocol)?

    public init(
        credentialRepository: any AgentCredentialRepositoryProtocol,
        sessionRepository: any AgentSessionRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        pendingPurposeRepository: (any PendingAgentPurposeRepositoryProtocol)? = nil
    ) {
        self.credentialRepository = credentialRepository
        self.sessionRepository = sessionRepository
        self.agentRepository = agentRepository
        self.pendingPurposeRepository = pendingPurposeRepository
    }

    /// Phase 4: projectId は必須
    /// Chat機能: pending purposeがあればそれをセッションに設定
    public func execute(agentId: String, passkey: String, projectId: String) throws -> AuthenticateResult {
        let agentID = AgentID(value: agentId)
        let projID = ProjectID(value: projectId)

        // エージェントの存在確認
        guard let agent = try agentRepository.findById(agentID) else {
            // セキュリティのため、エージェントが存在しない場合も同じエラーを返す
            return .failure(error: "Invalid agent_id or passkey")
        }

        // 認証情報の取得
        guard let credential = try credentialRepository.findByAgentId(agentID) else {
            // 認証情報がない場合も同じエラーを返す
            return .failure(error: "Invalid agent_id or passkey")
        }

        // パスキーの検証
        guard credential.verify(passkey: passkey) else {
            return .failure(error: "Invalid agent_id or passkey")
        }

        // 既存のセッションを無効化（オプション：同時ログインを許可しない場合）
        // try sessionRepository.deleteByAgentId(agentID)

        // Chat機能: pending purposeを確認
        var purpose: AgentPurpose = .task
        if let pendingRepo = pendingPurposeRepository,
           let pendingPurpose = try pendingRepo.find(agentId: agentID, projectId: projID) {
            purpose = pendingPurpose.purpose
            // 使用済みのpending purposeを削除（purpose指定で特定のpurposeのみ削除）
            try pendingRepo.delete(agentId: agentID, projectId: projID, purpose: purpose)
        }

        // Phase 4: 新しいセッションを作成（projectId, purpose を含む）
        let session = AgentSession(agentId: agentID, projectId: projID, purpose: purpose)
        try sessionRepository.save(session)

        // 認証情報のlastUsedAtを更新
        let updatedCredential = credential.withLastUsedAt(Date())
        try credentialRepository.save(updatedCredential)

        return .success(
            token: session.token,
            expiresIn: session.remainingSeconds,
            agentName: agent.name,
            systemPrompt: agent.systemPrompt
        )
    }
}

// MARK: - AuthenticateUseCaseV2

/// 状態ベースの認証ユースケース（Session Spawn Architecture対応）
/// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
///
/// 判定ロジック:
/// 1. タスクセッション判定（優先）: activeTaskSession == nil AND inProgressTask != nil
/// 2. チャットセッション判定: activeChatSession == nil AND chatPending != nil
/// 3. どちらにも該当しない場合は失敗
public struct AuthenticateUseCaseV2: Sendable {
    private let credentialRepository: any AgentCredentialRepositoryProtocol
    private let sessionRepository: any AgentSessionRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let pendingPurposeRepository: any PendingAgentPurposeRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol

    public init(
        credentialRepository: any AgentCredentialRepositoryProtocol,
        sessionRepository: any AgentSessionRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        pendingPurposeRepository: any PendingAgentPurposeRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol
    ) {
        self.credentialRepository = credentialRepository
        self.sessionRepository = sessionRepository
        self.agentRepository = agentRepository
        self.pendingPurposeRepository = pendingPurposeRepository
        self.taskRepository = taskRepository
    }

    public func execute(agentId: String, passkey: String, projectId: String) throws -> AuthenticateResult {
        let agentID = AgentID(value: agentId)
        let projID = ProjectID(value: projectId)

        // エージェントの存在確認
        guard let agent = try agentRepository.findById(agentID) else {
            return .failure(error: "Invalid agent_id or passkey")
        }

        // 認証情報の取得と検証
        guard let credential = try credentialRepository.findByAgentId(agentID) else {
            return .failure(error: "Invalid agent_id or passkey")
        }

        guard credential.verify(passkey: passkey) else {
            return .failure(error: "Invalid agent_id or passkey")
        }

        // 状態取得
        let allSessions = try sessionRepository.findByAgentIdAndProjectId(agentID, projectId: projID)
        let activeTaskSession = allSessions.first { $0.purpose == .task && !$0.isExpired }
        let activeChatSession = allSessions.first { $0.purpose == .chat && !$0.isExpired }

        let inProgressTask = try taskRepository.findByProject(projID, status: .inProgress)
            .first { $0.assigneeId == agentID }

        let chatPending = try pendingPurposeRepository.find(agentId: agentID, projectId: projID, purpose: .chat)

        // タスクセッション判定（優先）
        // 条件: activeTaskSession == nil AND inProgressTask != nil
        if activeTaskSession == nil && inProgressTask != nil {
            // タスクセッション作成
            let session = AgentSession(agentId: agentID, projectId: projID, purpose: .task)
            try sessionRepository.save(session)

            // task pending削除（あれば）
            if let _ = try pendingPurposeRepository.find(agentId: agentID, projectId: projID, purpose: .task) {
                try pendingPurposeRepository.delete(agentId: agentID, projectId: projID, purpose: .task)
            }

            // 認証情報のlastUsedAtを更新
            let updatedCredential = credential.withLastUsedAt(Date())
            try credentialRepository.save(updatedCredential)

            return .success(
                token: session.token,
                expiresIn: session.remainingSeconds,
                agentName: agent.name,
                systemPrompt: agent.systemPrompt
            )
        }

        // チャットセッション判定
        // 条件: activeChatSession == nil AND chatPending != nil
        if activeChatSession == nil && chatPending != nil {
            // チャットセッション作成
            let session = AgentSession(agentId: agentID, projectId: projID, purpose: .chat)
            try sessionRepository.save(session)

            // chat pending削除
            try pendingPurposeRepository.delete(agentId: agentID, projectId: projID, purpose: .chat)

            // 認証情報のlastUsedAtを更新
            let updatedCredential = credential.withLastUsedAt(Date())
            try credentialRepository.save(updatedCredential)

            return .success(
                token: session.token,
                expiresIn: session.remainingSeconds,
                agentName: agent.name,
                systemPrompt: agent.systemPrompt
            )
        }

        // どちらにも該当しない
        return .failure(error: "No valid purpose for authentication")
    }
}

// MARK: - LogoutUseCase

/// ログアウト（セッション無効化）ユースケース
public struct LogoutUseCase: Sendable {
    private let sessionRepository: any AgentSessionRepositoryProtocol

    public init(sessionRepository: any AgentSessionRepositoryProtocol) {
        self.sessionRepository = sessionRepository
    }

    public func execute(sessionToken: String) throws -> Bool {
        // セッションをトークンで検索
        guard let session = try sessionRepository.findByToken(sessionToken) else {
            // セッションが見つからない（既に無効または存在しない）
            return false
        }

        // セッションを削除
        try sessionRepository.delete(session.id)
        return true
    }
}

// MARK: - ValidateSessionUseCase

/// セッション検証ユースケース
public struct ValidateSessionUseCase: Sendable {
    private let sessionRepository: any AgentSessionRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol

    public init(
        sessionRepository: any AgentSessionRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol
    ) {
        self.sessionRepository = sessionRepository
        self.agentRepository = agentRepository
    }

    /// セッショントークンを検証し、有効な場合はエージェントIDを返す
    public func execute(sessionToken: String) throws -> AgentID? {
        guard let session = try sessionRepository.findByToken(sessionToken) else {
            return nil  // 無効なトークンまたは期限切れ
        }

        // エージェントの存在確認
        guard try agentRepository.findById(session.agentId) != nil else {
            return nil  // エージェントが削除されている
        }

        return session.agentId
    }
}

// MARK: - CleanupExpiredSessionsUseCase

/// 期限切れセッションのクリーンアップユースケース
public struct CleanupExpiredSessionsUseCase: Sendable {
    private let sessionRepository: any AgentSessionRepositoryProtocol

    public init(sessionRepository: any AgentSessionRepositoryProtocol) {
        self.sessionRepository = sessionRepository
    }

    public func execute() throws {
        try sessionRepository.deleteExpired()
    }
}

// MARK: - CreateCredentialUseCase

/// 認証情報作成ユースケース
public struct CreateCredentialUseCase: Sendable {
    private let credentialRepository: any AgentCredentialRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol

    public init(
        credentialRepository: any AgentCredentialRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol
    ) {
        self.credentialRepository = credentialRepository
        self.agentRepository = agentRepository
    }

    public func execute(agentId: AgentID, passkey: String) throws -> AgentCredential {
        // エージェントの存在確認
        guard try agentRepository.findById(agentId) != nil else {
            throw UseCaseError.agentNotFound(agentId)
        }

        // パスキーの検証
        guard passkey.count >= 8 else {
            throw UseCaseError.validationFailed("Passkey must be at least 8 characters")
        }

        // 既存の認証情報があれば削除
        if let existing = try credentialRepository.findByAgentId(agentId) {
            try credentialRepository.delete(existing.id)
        }

        // 新しい認証情報を作成
        let credential = AgentCredential(agentId: agentId, rawPasskey: passkey)
        try credentialRepository.save(credential)

        return credential
    }
}

// MARK: - DeleteCredentialUseCase

/// 認証情報削除ユースケース
public struct DeleteCredentialUseCase: Sendable {
    private let credentialRepository: any AgentCredentialRepositoryProtocol
    private let sessionRepository: any AgentSessionRepositoryProtocol

    public init(
        credentialRepository: any AgentCredentialRepositoryProtocol,
        sessionRepository: any AgentSessionRepositoryProtocol
    ) {
        self.credentialRepository = credentialRepository
        self.sessionRepository = sessionRepository
    }

    public func execute(agentId: AgentID) throws {
        // 認証情報を削除
        if let credential = try credentialRepository.findByAgentId(agentId) {
            try credentialRepository.delete(credential.id)
        }

        // 関連するセッションも削除
        try sessionRepository.deleteByAgentId(agentId)
    }
}
