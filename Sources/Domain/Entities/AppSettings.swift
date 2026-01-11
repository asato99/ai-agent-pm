// Sources/Domain/Entities/AppSettings.swift
// アプリケーション全体の設定を管理するエンティティ

import Foundation

/// アプリケーション設定エンティティ（シングルトンパターン）
/// データベースに1行のみ存在し、アプリ全体の設定を保持
public struct AppSettings: Sendable {
    /// シングルトン用の固定ID
    public static let singletonId = "app_settings"

    public let id: String

    /// MCP Coordinator Token（プレーンテキストで保存）
    /// デーモンとエージェント間の認証に使用
    public private(set) var coordinatorToken: String?

    public let createdAt: Date
    public var updatedAt: Date

    /// デフォルトのAppSettingsを作成
    public init(
        id: String = singletonId,
        coordinatorToken: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.coordinatorToken = coordinatorToken
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
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }

    /// コーディネータートークンをクリア
    public func clearCoordinatorToken() -> AppSettings {
        return AppSettings(
            id: self.id,
            coordinatorToken: nil,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}
