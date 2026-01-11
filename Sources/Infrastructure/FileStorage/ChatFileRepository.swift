// Sources/Infrastructure/FileStorage/ChatFileRepository.swift
// 参照: docs/design/CHAT_FEATURE.md - ChatFileRepository

import Foundation
import Domain

// MARK: - ChatFileRepositoryError

/// ChatFileRepository のエラー
public enum ChatFileRepositoryError: Error, LocalizedError {
    case workingDirectoryNotSet
    case encodingFailed(ChatMessage, Error)
    case decodingFailed(String, Error)
    case writeFailed(URL, Error)
    case readFailed(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .workingDirectoryNotSet:
            return "Project working directory is not set"
        case let .encodingFailed(message, error):
            return "Failed to encode message \(message.id.value): \(error.localizedDescription)"
        case let .decodingFailed(line, error):
            return "Failed to decode line: \(line.prefix(50))... Error: \(error.localizedDescription)"
        case let .writeFailed(url, error):
            return "Failed to write to \(url.path): \(error.localizedDescription)"
        case let .readFailed(url, error):
            return "Failed to read from \(url.path): \(error.localizedDescription)"
        }
    }
}

// MARK: - ChatFileRepository

/// ファイルベースのチャットリポジトリ
/// JSONL形式でメッセージを保存（1行1メッセージ、追記型）
///
/// ファイル形式:
/// ```jsonl
/// {"id":"msg_01","sender":"user","content":"Hello","createdAt":"2026-01-11T10:00:00Z"}
/// {"id":"msg_02","sender":"agent","content":"Hi!","createdAt":"2026-01-11T10:00:05Z"}
/// ```
public final class ChatFileRepository: ChatRepositoryProtocol, @unchecked Sendable {
    private let directoryManager: ProjectDirectoryManager
    private let projectRepository: ProjectRepositoryProtocol
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(
        directoryManager: ProjectDirectoryManager,
        projectRepository: ProjectRepositoryProtocol
    ) {
        self.directoryManager = directoryManager
        self.projectRepository = projectRepository

        // ISO8601 日時フォーマット
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - ChatRepositoryProtocol

    public func findMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage] {
        lock.lock()
        defer { lock.unlock() }

        let workingDir = try getWorkingDirectory(projectId: projectId)
        let chatFileURL = try directoryManager.getChatFilePath(
            workingDirectory: workingDir,
            agentId: agentId
        )

        return try readMessagesFromFile(at: chatFileURL)
    }

    public func saveMessage(_ message: ChatMessage, projectId: ProjectID, agentId: AgentID) throws {
        lock.lock()
        defer { lock.unlock() }

        let workingDir = try getWorkingDirectory(projectId: projectId)
        let chatFileURL = try directoryManager.getChatFilePath(
            workingDirectory: workingDir,
            agentId: agentId
        )

        try appendMessageToFile(message, at: chatFileURL)
    }

    public func getLastMessages(projectId: ProjectID, agentId: AgentID, limit: Int) throws -> [ChatMessage] {
        let allMessages = try findMessages(projectId: projectId, agentId: agentId)
        return Array(allMessages.suffix(limit))
    }

    public func findUnreadUserMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage] {
        let allMessages = try findMessages(projectId: projectId, agentId: agentId)

        // エージェントからの最後のメッセージのインデックスを探す
        guard let lastAgentMessageIndex = allMessages.lastIndex(where: { $0.sender == .agent }) else {
            // エージェントからのメッセージがない場合、全てのユーザーメッセージが未読
            return allMessages.filter { $0.sender == .user }
        }

        // 最後のエージェントメッセージ以降のユーザーメッセージを取得
        let messagesAfterLastAgent = allMessages[(lastAgentMessageIndex + 1)...]
        return messagesAfterLastAgent.filter { $0.sender == .user }
    }

    // MARK: - Private Methods

    /// プロジェクトIDから作業ディレクトリを取得
    private func getWorkingDirectory(projectId: ProjectID) throws -> String {
        guard let project = try projectRepository.findById(projectId),
              let workingDir = project.workingDirectory else {
            throw ChatFileRepositoryError.workingDirectoryNotSet
        }
        return workingDir
    }

    /// ファイルからメッセージを読み込み
    private func readMessagesFromFile(at url: URL) throws -> [ChatMessage] {
        // ファイルが存在しない場合は空配列を返す
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ChatFileRepositoryError.readFailed(url, error)
        }

        // 空ファイルの場合は空配列を返す
        guard !content.isEmpty else {
            return []
        }

        var messages: [ChatMessage] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }

            guard let data = trimmedLine.data(using: .utf8) else { continue }

            do {
                let message = try decoder.decode(ChatMessage.self, from: data)
                messages.append(message)
            } catch {
                // パース失敗した行はスキップ（ログは出すが処理は継続）
                print("[ChatFileRepository] Warning: Failed to decode line: \(error)")
            }
        }

        return messages
    }

    /// メッセージをファイルに追記
    private func appendMessageToFile(_ message: ChatMessage, at url: URL) throws {
        let jsonData: Data
        do {
            jsonData = try encoder.encode(message)
        } catch {
            throw ChatFileRepositoryError.encodingFailed(message, error)
        }

        guard var jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ChatFileRepositoryError.encodingFailed(message, NSError(domain: "ChatFileRepository", code: -1))
        }

        // 改行を追加
        jsonString += "\n"

        // ファイルが存在しない場合は新規作成
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try jsonString.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw ChatFileRepositoryError.writeFailed(url, error)
            }
            return
        }

        // 既存ファイルに追記
        do {
            let fileHandle = try FileHandle(forWritingTo: url)
            defer { try? fileHandle.close() }
            try fileHandle.seekToEnd()
            guard let data = jsonString.data(using: .utf8) else {
                throw ChatFileRepositoryError.writeFailed(url, NSError(domain: "ChatFileRepository", code: -2))
            }
            try fileHandle.write(contentsOf: data)
        } catch let error as ChatFileRepositoryError {
            throw error
        } catch {
            throw ChatFileRepositoryError.writeFailed(url, error)
        }
    }
}
