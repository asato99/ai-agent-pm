// Sources/Infrastructure/Database/DatabaseSetup.swift
// 参照: docs/architecture/DATABASE_SCHEMA.md - スキーマ定義
// 参照: docs/guide/CLEAN_ARCHITECTURE.md - Infrastructure層

import Foundation
import GRDB

/// データベースのセットアップとマイグレーションを管理
public final class DatabaseSetup {

    /// データベースを作成または開く
    /// - Parameter path: データベースファイルのパス
    /// - Returns: 設定済みのDatabaseQueue
    public static func createDatabase(at path: String) throws -> DatabaseQueue {
        // ディレクトリが存在しない場合は作成
        let directory = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: directory) {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
        }

        // 既存DBがある場合、外部キー無効状態でクリーンアップを先に実行
        // （マイグレーション前に外部キー違反を解消）
        if FileManager.default.fileExists(atPath: path) {
            try cleanupOrphanedRecords(at: path)
        }

        // WALモードを有効化した設定を作成
        var configuration = Configuration()

        // マルチプロセス同時アクセス対応: ビジータイムアウト設定
        // AppとMCPサーバーが同時にDBにアクセスする際のロック待機時間
        configuration.busyMode = .timeout(5.0) // 5秒待機

        configuration.prepareDatabase { db in
            // WALモードを有効化（同時アクセス対応）
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // 外部キー制約を有効化
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // 同期モードをNORMALに設定（パフォーマンスと安全性のバランス）
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }

        let dbQueue = try DatabaseQueue(path: path, configuration: configuration)

        // マイグレーション実行
        try migrate(dbQueue)

        return dbQueue
    }

    /// 外部キー無効状態で孤立レコードをクリーンアップ
    /// マイグレーション前に外部キー違反を解消する
    private static func cleanupOrphanedRecords(at path: String) throws {
        var cleanupConfig = Configuration()
        cleanupConfig.busyMode = .timeout(5.0)
        cleanupConfig.prepareDatabase { db in
            // 外部キーを無効化した状態でクリーンアップ
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
        }

        let cleanupQueue = try DatabaseQueue(path: path, configuration: cleanupConfig)
        try cleanupQueue.write { db in
            let hasTasks = try tableExists(db, name: "tasks")
            let hasAgents = try tableExists(db, name: "agents")
            let hasProjects = try tableExists(db, name: "projects")

            // execution_logs の孤立レコードを削除
            if try tableExists(db, name: "execution_logs") && hasTasks {
                try db.execute(sql: """
                    DELETE FROM execution_logs
                    WHERE task_id NOT IN (SELECT id FROM tasks)
                """)
            }

            // contexts の孤立レコードを削除
            if try tableExists(db, name: "contexts") && hasTasks {
                try db.execute(sql: """
                    DELETE FROM contexts
                    WHERE task_id NOT IN (SELECT id FROM tasks)
                """)
            }

            // agent_sessions の孤立レコードを削除
            if try tableExists(db, name: "agent_sessions") && hasAgents {
                try db.execute(sql: """
                    DELETE FROM agent_sessions
                    WHERE agent_id NOT IN (SELECT id FROM agents)
                """)
            }

            // handoffs の孤立レコードを削除
            if try tableExists(db, name: "handoffs") && hasTasks {
                try db.execute(sql: """
                    DELETE FROM handoffs
                    WHERE task_id NOT IN (SELECT id FROM tasks)
                """)
            }

            // tasks の孤立レコードを削除（存在しないプロジェクト参照）
            if hasTasks && hasProjects {
                try db.execute(sql: """
                    DELETE FROM tasks
                    WHERE project_id NOT IN (SELECT id FROM projects)
                """)
            }
        }
    }

    /// テーブルが存在するかチェック
    private static func tableExists(_ db: Database, name: String) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT COUNT(*) > 0 FROM sqlite_master
            WHERE type = 'table' AND name = ?
        """, arguments: [name]) ?? false
    }

    // MARK: - Migration

    /// マイグレーションを実行
    /// 各グループは Migrations/ 配下の DatabaseMigrator extension で定義
    private static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerV001toV010()
        migrator.registerV011toV020()
        migrator.registerV021toV030()
        migrator.registerV031toV040()
        migrator.registerV041toV051()
        try migrator.migrate(dbQueue)
    }

    // MARK: - ZIP Helpers (used by v45 migration)

    /// content文字列からSKILL.mdのみを含むZIPアーカイブを作成
    static func createZipArchive(skillMdContent: String) -> Data {
        // 簡易的なZIP作成（SKILL.mdのみ、非圧縮）
        // ZIPフォーマット: https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
        var data = Data()
        let fileName = "SKILL.md"
        let fileNameData = fileName.data(using: .utf8)!
        let contentData = skillMdContent.data(using: .utf8)!

        // Local file header
        data.append(contentsOf: [0x50, 0x4b, 0x03, 0x04]) // signature
        data.append(contentsOf: [0x0a, 0x00]) // version needed (1.0)
        data.append(contentsOf: [0x00, 0x00]) // flags
        data.append(contentsOf: [0x00, 0x00]) // compression (stored)
        data.append(contentsOf: [0x00, 0x00]) // mod time
        data.append(contentsOf: [0x00, 0x00]) // mod date
        let crc = crc32(contentData)
        data.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) }) // compressed size
        data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) }) // uncompressed size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) }) // file name length
        data.append(contentsOf: [0x00, 0x00]) // extra field length
        data.append(fileNameData)
        let localHeaderOffset = 0
        data.append(contentData)

        // Central directory header
        let centralDirOffset = data.count
        data.append(contentsOf: [0x50, 0x4b, 0x01, 0x02]) // signature
        data.append(contentsOf: [0x14, 0x00]) // version made by
        data.append(contentsOf: [0x0a, 0x00]) // version needed
        data.append(contentsOf: [0x00, 0x00]) // flags
        data.append(contentsOf: [0x00, 0x00]) // compression
        data.append(contentsOf: [0x00, 0x00]) // mod time
        data.append(contentsOf: [0x00, 0x00]) // mod date
        data.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x00]) // extra field length
        data.append(contentsOf: [0x00, 0x00]) // file comment length
        data.append(contentsOf: [0x00, 0x00]) // disk number
        data.append(contentsOf: [0x00, 0x00]) // internal file attributes
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // external file attributes
        data.append(contentsOf: withUnsafeBytes(of: UInt32(localHeaderOffset).littleEndian) { Array($0) })
        data.append(fileNameData)
        let centralDirSize = data.count - centralDirOffset

        // End of central directory
        data.append(contentsOf: [0x50, 0x4b, 0x05, 0x06]) // signature
        data.append(contentsOf: [0x00, 0x00]) // disk number
        data.append(contentsOf: [0x00, 0x00]) // disk with central dir
        data.append(contentsOf: [0x01, 0x00]) // entries on disk
        data.append(contentsOf: [0x01, 0x00]) // total entries
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirSize).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirOffset).littleEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x00]) // comment length

        return data
    }

    /// CRC-32を計算
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
