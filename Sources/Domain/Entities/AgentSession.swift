// Sources/Domain/Entities/AgentSession.swift
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-1 認証基盤
// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md - (agent_id, project_id) 単位のセッション管理
// 参照: docs/design/CHAT_FEATURE.md - セッションの起動理由(purpose)管理

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
    /// Feature 14: セッション有効期限（一時停止時に短縮される可能性がある）
    public var expiresAt: Date
    public let createdAt: Date

    // MARK: - Purpose Field
    /// セッションの起動理由（task=タスク実行, chat=チャット応答）
    public var purpose: AgentPurpose

    // MARK: - Activity Tracking
    /// 最終アクティビティ日時（アイドルタイムアウト判定用）
    public var lastActivityAt: Date

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
    /// Chat機能: purpose はデフォルトで .task
    public init(
        id: AgentSessionID = .generate(),
        agentId: AgentID,
        projectId: ProjectID,
        purpose: AgentPurpose = .task,
        expiresAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.token = Self.generateToken()
        self.agentId = agentId
        self.projectId = projectId
        self.purpose = purpose
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(Self.defaultExpirationInterval)
        self.createdAt = createdAt
        self.lastActivityAt = createdAt  // 作成時が最初のアクティビティ
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
        purpose: AgentPurpose = .task,
        expiresAt: Date,
        createdAt: Date,
        lastActivityAt: Date? = nil,
        reportedProvider: String? = nil,
        reportedModel: String? = nil,
        modelVerified: Bool? = nil,
        modelVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.token = token
        self.agentId = agentId
        self.projectId = projectId
        self.purpose = purpose
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt ?? createdAt  // 既存データはcreatedAtで初期化
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
