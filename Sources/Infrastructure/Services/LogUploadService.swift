// Sources/Infrastructure/Services/LogUploadService.swift
// ログアップロードサービス
// 参照: docs/design/LOG_TRANSFER_DESIGN.md

import Foundation
import Domain

// MARK: - LogUploadError

/// ログアップロードエラー
public enum LogUploadError: Error, LocalizedError {
    case notImplemented
    case projectNotFound
    case workingDirectoryNotConfigured
    case fileTooLarge(maxMB: Int, actualMB: Double)
    case fileWriteFailed(Error)
    case executionLogNotFound

    public var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "LogUploadService is not implemented"
        case .projectNotFound:
            return "Project not found"
        case .workingDirectoryNotConfigured:
            return "Project working directory is not configured"
        case let .fileTooLarge(maxMB, actualMB):
            return "File too large: \(String(format: "%.2f", actualMB))MB exceeds \(maxMB)MB limit"
        case let .fileWriteFailed(error):
            return "Failed to write log file: \(error.localizedDescription)"
        case .executionLogNotFound:
            return "Execution log not found"
        }
    }
}

// MARK: - LogUploadService

/// ログアップロードサービス
/// CoordinatorからのログファイルアップロードをRESTサーバー経由で処理
public struct LogUploadService {
    private let directoryManager: ProjectDirectoryManager
    private let projectRepository: ProjectRepository
    private let executionLogRepository: ExecutionLogRepository
    private let maxFileSizeMB: Int
    private let fileManager: FileManager

    public init(
        directoryManager: ProjectDirectoryManager,
        projectRepository: ProjectRepository,
        executionLogRepository: ExecutionLogRepository,
        maxFileSizeMB: Int = 10,
        fileManager: FileManager = .default
    ) {
        self.directoryManager = directoryManager
        self.projectRepository = projectRepository
        self.executionLogRepository = executionLogRepository
        self.maxFileSizeMB = maxFileSizeMB
        self.fileManager = fileManager
    }

    // MARK: - Result Type

    public struct UploadResult {
        public let success: Bool
        public let logFilePath: String?
        public let fileSize: Int

        public init(success: Bool, logFilePath: String?, fileSize: Int) {
            self.success = success
            self.logFilePath = logFilePath
            self.fileSize = fileSize
        }
    }

    // MARK: - Public Methods

    /// ログファイルをアップロード
    /// - Parameters:
    ///   - executionLogId: 実行ログID
    ///   - agentId: エージェントID
    ///   - taskId: タスクID
    ///   - projectId: プロジェクトID
    ///   - logData: ログファイルのバイナリデータ
    ///   - originalFilename: 元のファイル名
    /// - Returns: アップロード結果
    /// - Throws: LogUploadError
    public func uploadLog(
        executionLogId: String,
        agentId: String,
        taskId: String,
        projectId: String,
        logData: Data,
        originalFilename: String
    ) throws -> UploadResult {
        // 1. ファイルサイズチェック
        let fileSizeBytes = logData.count
        let fileSizeMB = Double(fileSizeBytes) / (1024 * 1024)
        if fileSizeMB > Double(maxFileSizeMB) {
            throw LogUploadError.fileTooLarge(maxMB: maxFileSizeMB, actualMB: fileSizeMB)
        }

        // 2. プロジェクト取得
        let projectID = ProjectID(value: projectId)
        guard let project = try projectRepository.findById(projectID) else {
            throw LogUploadError.projectNotFound
        }

        // 3. workingDirectory確認
        guard let workingDirectory = project.workingDirectory else {
            throw LogUploadError.workingDirectoryNotConfigured
        }

        // 4. ログディレクトリ作成
        let agentID = AgentID(value: agentId)
        let logDirURL = try directoryManager.getOrCreateLogDirectory(
            workingDirectory: workingDirectory,
            agentId: agentID
        )

        // 5. ログファイル保存
        let logFileURL = logDirURL.appendingPathComponent(originalFilename)
        do {
            try logData.write(to: logFileURL)
        } catch {
            throw LogUploadError.fileWriteFailed(error)
        }

        // 6. ExecutionLog更新
        let execLogID = ExecutionLogID(value: executionLogId)
        if var executionLog = try executionLogRepository.findById(execLogID) {
            executionLog.setLogFilePath(logFileURL.path)
            try executionLogRepository.save(executionLog)
        }

        return UploadResult(
            success: true,
            logFilePath: logFileURL.path,
            fileSize: fileSizeBytes
        )
    }
}
