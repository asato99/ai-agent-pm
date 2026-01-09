// Sources/Domain/Entities/AgentSession.swift
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-1 認証基盤
// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md - (agent_id, project_id) 単位のセッション管理

import Foundation

/// エージェントの認証セッションを表すエンティティ
/// 認証成功後に発行され、一定時間後に失効する
/// Phase 4: セッションは (agent_id, project_id) の組み合わせに紐づく
public struct AgentSession: Identifiable, Equatable, Sendable {
    /// デフォルトのセッション有効期間（1時間）
    public static let defaultExpirationInterval: TimeInterval = 3600

    public let id: AgentSessionID
    public let token: String
    public let agentId: AgentID
    /// Phase 4: セッションが紐づくプロジェクトID
    public let projectId: ProjectID
    public let expiresAt: Date
    public let createdAt: Date

    // MARK: - Model Verification Fields
    /// Agent Instanceが申告したプロバイダー
    public var reportedProvider: String?
    /// Agent Instanceが申告したモデルID
    public var reportedModel: String?
    /// モデル検証結果（nil=未検証, true=一致, false=不一致）
    public var modelVerified: Bool?
    /// モデル検証日時
    public var modelVerifiedAt: Date?

    /// セッションが期限切れかどうか
    public var isExpired: Bool {
        Date() > expiresAt
    }

    /// セッションの残り有効時間（秒）。期限切れの場合は0
    public var remainingSeconds: Int {
        let remaining = expiresAt.timeIntervalSince(Date())
        return max(0, Int(remaining))
    }

    /// 新しいセッションを生成
    /// Phase 4: projectId は必須
    public init(
        id: AgentSessionID = .generate(),
        agentId: AgentID,
        projectId: ProjectID,
        expiresAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.token = Self.generateToken()
        self.agentId = agentId
        self.projectId = projectId
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(Self.defaultExpirationInterval)
        self.createdAt = createdAt
        self.reportedProvider = nil
        self.reportedModel = nil
        self.modelVerified = nil
        self.modelVerifiedAt = nil
    }

    /// DBから復元用（トークンを直接設定）
    public init(
        id: AgentSessionID,
        token: String,
        agentId: AgentID,
        projectId: ProjectID,
        expiresAt: Date,
        createdAt: Date,
        reportedProvider: String? = nil,
        reportedModel: String? = nil,
        modelVerified: Bool? = nil,
        modelVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.token = token
        self.agentId = agentId
        self.projectId = projectId
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.reportedProvider = reportedProvider
        self.reportedModel = reportedModel
        self.modelVerified = modelVerified
        self.modelVerifiedAt = modelVerifiedAt
    }

    // MARK: - Private

    /// ユニークなセッショントークンを生成
    private static func generateToken() -> String {
        "sess_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }
}
