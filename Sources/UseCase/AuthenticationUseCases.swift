// Sources/UseCase/AuthenticationUseCases.swift
// 認証関連のユースケース (Phase 3-1)
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md

import Foundation
import Domain

// MARK: - AuthenticateResult

/// 認証結果
public struct AuthenticateResult: Sendable {
    public let success: Bool
    public let sessionToken: String?
    public let expiresIn: Int?  // 秒数
    public let agentName: String?
    public let error: String?

    public static func success(token: String, expiresIn: Int, agentName: String) -> AuthenticateResult {
        AuthenticateResult(
            success: true,
            sessionToken: token,
            expiresIn: expiresIn,
            agentName: agentName,
            error: nil
        )
    }

    public static func failure(error: String) -> AuthenticateResult {
        AuthenticateResult(
            success: false,
            sessionToken: nil,
            expiresIn: nil,
            agentName: nil,
            error: error
        )
    }
}

// MARK: - AuthenticateUseCase

/// エージェント認証ユースケース
public struct AuthenticateUseCase: Sendable {
    private let credentialRepository: any AgentCredentialRepositoryProtocol
    private let sessionRepository: any AgentSessionRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol

    public init(
        credentialRepository: any AgentCredentialRepositoryProtocol,
        sessionRepository: any AgentSessionRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol
    ) {
        self.credentialRepository = credentialRepository
        self.sessionRepository = sessionRepository
        self.agentRepository = agentRepository
    }

    public func execute(agentId: String, passkey: String) throws -> AuthenticateResult {
        let agentID = AgentID(value: agentId)

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

        // 新しいセッションを作成
        let session = AgentSession(agentId: agentID)
        try sessionRepository.save(session)

        // 認証情報のlastUsedAtを更新
        let updatedCredential = credential.withLastUsedAt(Date())
        try credentialRepository.save(updatedCredential)

        return .success(
            token: session.token,
            expiresIn: session.remainingSeconds,
            agentName: agent.name
        )
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
