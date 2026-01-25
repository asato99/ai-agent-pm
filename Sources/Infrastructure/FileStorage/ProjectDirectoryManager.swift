// Sources/Infrastructure/FileStorage/ProjectDirectoryManager.swift
// 参照: docs/design/CHAT_FEATURE.md - ディレクトリ構成

import Foundation
import Domain

// MARK: - ProjectDirectoryManagerError

/// ProjectDirectoryManager のエラー
public enum ProjectDirectoryManagerError: Error, LocalizedError {
    case workingDirectoryNotSet
    case directoryCreationFailed(URL, Error)
    case fileCreationFailed(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .workingDirectoryNotSet:
            return "Project working directory is not set"
        case let .directoryCreationFailed(url, error):
            return "Failed to create directory at \(url.path): \(error.localizedDescription)"
        case let .fileCreationFailed(url, error):
            return "Failed to create file at \(url.path): \(error.localizedDescription)"
        }
    }
}

// MARK: - ProjectDirectoryManager

/// .ai-pm ディレクトリの管理
/// ファイルベースストレージ用のディレクトリ構造を管理する
///
/// ディレクトリ構成:
/// ```
/// {project.workingDirectory}/
/// └── .ai-pm/
///     ├── .gitignore
///     └── agents/
///         └── {agent-id}/
///             └── chat.jsonl
/// ```
public final class ProjectDirectoryManager: Sendable {
    /// アプリ専用ディレクトリ名
    private static let appDirectoryName = ".ai-pm"
    /// エージェントディレクトリ名
    private static let agentsDirectoryName = "agents"
    /// ログディレクトリ名
    private static let logsDirectoryName = "logs"
    /// チャットファイル名
    private static let chatFileName = "chat.jsonl"
    /// .gitignore の内容
    private static let gitignoreContent = """
        # AI Agent PM - auto-generated
        chat.jsonl
        context.md
        logs/
        """

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public Methods

    /// プロジェクトの .ai-pm ディレクトリのパスを取得
    /// - Parameter workingDirectory: プロジェクトの作業ディレクトリ
    /// - Returns: .ai-pm ディレクトリの URL
    /// - Throws: workingDirectory が nil の場合
    public func getAppDirectoryURL(workingDirectory: String?) throws -> URL {
        guard let workingDir = workingDirectory else {
            throw ProjectDirectoryManagerError.workingDirectoryNotSet
        }
        return URL(fileURLWithPath: workingDir)
            .appendingPathComponent(Self.appDirectoryName)
    }

    /// プロジェクトの .ai-pm ディレクトリを取得（なければ作成）
    /// - Parameter workingDirectory: プロジェクトの作業ディレクトリ
    /// - Returns: .ai-pm ディレクトリの URL
    public func getOrCreateAppDirectory(workingDirectory: String?) throws -> URL {
        let appDirURL = try getAppDirectoryURL(workingDirectory: workingDirectory)
        try createDirectoryIfNeeded(at: appDirURL)
        try createGitignoreIfNeeded(in: appDirURL)
        return appDirURL
    }

    /// エージェント用ディレクトリのパスを取得（なければ作成）
    /// - Parameters:
    ///   - workingDirectory: プロジェクトの作業ディレクトリ
    ///   - agentId: エージェントID
    /// - Returns: エージェントディレクトリの URL
    public func getOrCreateAgentDirectory(workingDirectory: String?, agentId: AgentID) throws -> URL {
        let appDirURL = try getOrCreateAppDirectory(workingDirectory: workingDirectory)
        let agentsDirURL = appDirURL.appendingPathComponent(Self.agentsDirectoryName)
        try createDirectoryIfNeeded(at: agentsDirURL)

        let agentDirURL = agentsDirURL.appendingPathComponent(agentId.value)
        try createDirectoryIfNeeded(at: agentDirURL)
        return agentDirURL
    }

    /// 実行ログ用ディレクトリのパスを取得（なければ作成）
    /// - Parameters:
    ///   - workingDirectory: プロジェクトの作業ディレクトリ
    ///   - agentId: エージェントID
    /// - Returns: ログディレクトリの URL
    /// - Throws: workingDirectory が nil の場合
    ///
    /// ディレクトリ構成:
    /// ```
    /// {project.workingDirectory}/
    /// └── .ai-pm/
    ///     └── logs/
    ///         └── {agent-id}/
    ///             ├── 20260125_143022.log
    ///             └── ...
    /// ```
    public func getOrCreateLogDirectory(workingDirectory: String?, agentId: AgentID) throws -> URL {
        let appDirURL = try getOrCreateAppDirectory(workingDirectory: workingDirectory)
        let logsDirURL = appDirURL.appendingPathComponent(Self.logsDirectoryName)
        try createDirectoryIfNeeded(at: logsDirURL)

        let agentLogDirURL = logsDirURL.appendingPathComponent(agentId.value)
        try createDirectoryIfNeeded(at: agentLogDirURL)
        return agentLogDirURL
    }

    /// チャットファイルのパスを取得
    /// - Parameters:
    ///   - workingDirectory: プロジェクトの作業ディレクトリ
    ///   - agentId: エージェントID
    /// - Returns: チャットファイルの URL
    public func getChatFilePath(workingDirectory: String?, agentId: AgentID) throws -> URL {
        let agentDirURL = try getOrCreateAgentDirectory(workingDirectory: workingDirectory, agentId: agentId)
        return agentDirURL.appendingPathComponent(Self.chatFileName)
    }

    /// チャットファイルが存在するか確認
    /// - Parameters:
    ///   - workingDirectory: プロジェクトの作業ディレクトリ
    ///   - agentId: エージェントID
    /// - Returns: ファイルが存在する場合 true
    public func chatFileExists(workingDirectory: String?, agentId: AgentID) throws -> Bool {
        let chatFileURL = try getChatFilePath(workingDirectory: workingDirectory, agentId: agentId)
        return fileManager.fileExists(atPath: chatFileURL.path)
    }

    // MARK: - Private Methods

    /// ディレクトリが存在しなければ作成
    private func createDirectoryIfNeeded(at url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ProjectDirectoryManagerError.directoryCreationFailed(url, error)
        }
    }

    /// .gitignore が存在しなければ作成
    private func createGitignoreIfNeeded(in directoryURL: URL) throws {
        let gitignoreURL = directoryURL.appendingPathComponent(".gitignore")
        guard !fileManager.fileExists(atPath: gitignoreURL.path) else { return }
        do {
            try Self.gitignoreContent.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        } catch {
            throw ProjectDirectoryManagerError.fileCreationFailed(gitignoreURL, error)
        }
    }
}
