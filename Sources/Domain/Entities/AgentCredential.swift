// Sources/Domain/Entities/AgentCredential.swift
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-1 認証基盤

import Foundation
import CryptoKit

/// エージェントの認証情報を表すエンティティ
/// Passkeyをハッシュ化して保存し、認証時に検証する
public struct AgentCredential: Identifiable, Equatable, Sendable {
    public let id: AgentCredentialID
    public let agentId: AgentID
    public let passkeyHash: String
    public let salt: String
    public let createdAt: Date
    public var lastUsedAt: Date?

    /// 新しい認証情報を生成パスキーをハッシュ化
    public init(
        id: AgentCredentialID = .generate(),
        agentId: AgentID,
        rawPasskey: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.agentId = agentId
        self.salt = Self.generateSalt()
        self.passkeyHash = Self.hashPasskey(rawPasskey, salt: self.salt)
        self.createdAt = createdAt
        self.lastUsedAt = nil
    }

    /// DBから復元用（ハッシュ済みの値を直接設定）
    public init(
        id: AgentCredentialID,
        agentId: AgentID,
        passkeyHash: String,
        salt: String,
        createdAt: Date,
        lastUsedAt: Date?
    ) {
        self.id = id
        self.agentId = agentId
        self.passkeyHash = passkeyHash
        self.salt = salt
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// パスキーを検証する
    /// - Parameter passkey: 検証するパスキー（平文）
    /// - Returns: パスキーが正しい場合true
    public func verify(passkey: String) -> Bool {
        let hash = Self.hashPasskey(passkey, salt: salt)
        return hash == passkeyHash
    }

    /// lastUsedAtを更新した新しいインスタンスを返す
    public func withLastUsedAt(_ date: Date) -> AgentCredential {
        AgentCredential(
            id: id,
            agentId: agentId,
            passkeyHash: passkeyHash,
            salt: salt,
            createdAt: createdAt,
            lastUsedAt: date
        )
    }

    // MARK: - Private

    /// ランダムなソルトを生成
    private static func generateSalt() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }

    /// パスキーをハッシュ化（SHA256 + salt）
    private static func hashPasskey(_ passkey: String, salt: String) -> String {
        let combined = passkey + salt
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
