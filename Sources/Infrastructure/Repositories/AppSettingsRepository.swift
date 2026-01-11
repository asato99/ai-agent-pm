// Sources/Infrastructure/Repositories/AppSettingsRepository.swift
// アプリケーション全体の設定リポジトリ

import Foundation
import GRDB
import Domain

// MARK: - AppSettingsRecord

/// GRDB用のAppSettingsレコード
struct AppSettingsRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "app_settings"

    var id: String
    var coordinatorToken: String?
    var pendingPurposeTTLSeconds: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case coordinatorToken = "coordinator_token"
        case pendingPurposeTTLSeconds = "pending_purpose_ttl_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> AppSettings {
        AppSettings(
            id: id,
            coordinatorToken: coordinatorToken,
            pendingPurposeTTLSeconds: pendingPurposeTTLSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func fromDomain(_ settings: AppSettings) -> AppSettingsRecord {
        AppSettingsRecord(
            id: settings.id,
            coordinatorToken: settings.coordinatorToken,
            pendingPurposeTTLSeconds: settings.pendingPurposeTTLSeconds,
            createdAt: settings.createdAt,
            updatedAt: settings.updatedAt
        )
    }
}

// MARK: - AppSettingsRepository

/// アプリケーション設定リポジトリ
/// シングルトンパターン: DBに1行のみ存在
public final class AppSettingsRepository: AppSettingsRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func get() throws -> AppSettings {
        try db.write { db in
            // 既存の設定を取得
            if let record = try AppSettingsRecord
                .filter(Column("id") == AppSettings.singletonId)
                .fetchOne(db) {
                return record.toDomain()
            }

            // 存在しない場合はデフォルトを作成
            let defaultSettings = AppSettings()
            let record = AppSettingsRecord.fromDomain(defaultSettings)
            try record.insert(db)
            return defaultSettings
        }
    }

    public func save(_ settings: AppSettings) throws {
        try db.write { db in
            try AppSettingsRecord.fromDomain(settings).save(db)
        }
    }
}
