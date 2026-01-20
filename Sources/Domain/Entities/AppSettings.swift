// Sources/Domain/Entities/AppSettings.swift
// アプリケーション全体の設定を管理するエンティティ

import Foundation

/// アプリケーション設定エンティティ（シングルトンパターン）
/// データベースに1行のみ存在し、アプリ全体の設定を保持
public struct AppSettings: Sendable {
    /// シングルトン用の固定ID
    public static let singletonId = "app_settings"

    /// デフォルトのPending Purpose TTL（5分 = 300秒）
    public static let defaultPendingPurposeTTLSeconds: Int = 300

    public let id: String

    /// MCP Coordinator Token（プレーンテキストで保存）
    /// デーモンとエージェント間の認証に使用
    public private(set) var coordinatorToken: String?

    /// Pending Purpose のTTL（秒）
    /// エージェント起動理由（chat/task）が有効な期間
    public var pendingPurposeTTLSeconds: Int

    /// リモートアクセス許可フラグ
    /// trueの場合、REST APIが0.0.0.0にバインドされ、LAN内の別端末からアクセス可能になる
    /// デフォルト: false（127.0.0.1のみ）
    public var allowRemoteAccess: Bool

    public let createdAt: Date
    public var updatedAt: Date

    /// デフォルトのAppSettingsを作成
    public init(
        id: String = singletonId,
        coordinatorToken: String? = nil,
        pendingPurposeTTLSeconds: Int = defaultPendingPurposeTTLSeconds,
        allowRemoteAccess: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.coordinatorToken = coordinatorToken
        self.pendingPurposeTTLSeconds = pendingPurposeTTLSeconds
        self.allowRemoteAccess = allowRemoteAccess
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 新しいランダムなコーディネータートークンを生成
    /// 32バイトのランダムデータをBase64エンコード
    public func regenerateCoordinatorToken() -> AppSettings {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        let token = Data(bytes).base64EncodedString()

        return AppSettings(
            id: self.id,
            coordinatorToken: token,
            pendingPurposeTTLSeconds: self.pendingPurposeTTLSeconds,
            allowRemoteAccess: self.allowRemoteAccess,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }

    /// コーディネータートークンをクリア
    public func clearCoordinatorToken() -> AppSettings {
        return AppSettings(
            id: self.id,
            coordinatorToken: nil,
            pendingPurposeTTLSeconds: self.pendingPurposeTTLSeconds,
            allowRemoteAccess: self.allowRemoteAccess,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }

    /// Pending Purpose TTLを更新
    public func withPendingPurposeTTL(_ seconds: Int) -> AppSettings {
        return AppSettings(
            id: self.id,
            coordinatorToken: self.coordinatorToken,
            pendingPurposeTTLSeconds: seconds,
            allowRemoteAccess: self.allowRemoteAccess,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }

    /// リモートアクセス設定を更新
    public func withAllowRemoteAccess(_ allow: Bool) -> AppSettings {
        return AppSettings(
            id: self.id,
            coordinatorToken: self.coordinatorToken,
            pendingPurposeTTLSeconds: self.pendingPurposeTTLSeconds,
            allowRemoteAccess: allow,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}
