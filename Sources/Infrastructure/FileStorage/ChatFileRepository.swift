// Sources/Infrastructure/FileStorage/ChatFileRepository.swift
// Reference: docs/design/CHAT_FEATURE.md - Section 2.3

import Foundation
import Domain

// MARK: - ChatFileRepositoryError

/// ChatFileRepository errors
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

/// File-based chat repository
/// JSONL format for message storage (one message per line, append-only)
///
/// Storage format (sender's storage):
/// ```jsonl
/// {"id":"msg_01","senderId":"owner-1","receiverId":"worker-1","content":"Hello","createdAt":"..."}
/// ```
///
/// Storage format (receiver's storage):
/// ```jsonl
/// {"id":"msg_01","senderId":"owner-1","content":"Hello","createdAt":"..."}
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

        // ISO8601 date format
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

    /// Find unread messages (messages from others after my last message)
    /// Uses senderId to identify who sent each message
    public func findUnreadMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage] {
        let allMessages = try findMessages(projectId: projectId, agentId: agentId)

        // Find the index of my last sent message
        guard let lastSentIndex = allMessages.lastIndex(where: { $0.senderId == agentId }) else {
            // No messages from me, all messages from others are unread
            return allMessages.filter { $0.senderId != agentId }
        }

        // Get messages after my last sent message that are from others
        let messagesAfterLastSent = allMessages[(lastSentIndex + 1)...]
        return messagesAfterLastSent.filter { $0.senderId != agentId }
    }

    // MARK: - Dual Write (双方向保存)

    /// Save message to both sender's and receiver's storage
    /// - Sender's storage: includes receiverId
    /// - Receiver's storage: receiverId is nil
    public func saveMessageDualWrite(
        _ message: ChatMessage,
        projectId: ProjectID,
        senderAgentId: AgentID,
        receiverAgentId: AgentID
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let workingDir = try getWorkingDirectory(projectId: projectId)

        // 1. Save to sender's storage (with receiverId)
        let senderFileURL = try directoryManager.getChatFilePath(
            workingDirectory: workingDir,
            agentId: senderAgentId
        )
        try appendMessageToFile(message, at: senderFileURL)

        // 2. Save to receiver's storage (without receiverId)
        let receiverMessage = message.withoutReceiverId()
        let receiverFileURL = try directoryManager.getChatFilePath(
            workingDirectory: workingDir,
            agentId: receiverAgentId
        )
        try appendMessageToFile(receiverMessage, at: receiverFileURL)
    }

    // MARK: - Pagination (REST API)

    public func findMessagesWithCursor(
        projectId: ProjectID,
        agentId: AgentID,
        limit: Int,
        after: ChatMessageID?,
        before: ChatMessageID?
    ) throws -> ChatMessagePage {
        let allMessages = try findMessages(projectId: projectId, agentId: agentId)

        var filteredMessages = allMessages

        // after cursor: get messages after the specified ID
        if let afterId = after {
            if let afterIndex = allMessages.firstIndex(where: { $0.id == afterId }) {
                filteredMessages = Array(allMessages.suffix(from: afterIndex + 1))
            }
        }

        // before cursor: get messages before the specified ID
        if let beforeId = before {
            if let beforeIndex = filteredMessages.firstIndex(where: { $0.id == beforeId }) {
                filteredMessages = Array(filteredMessages.prefix(beforeIndex))
            }
        }

        // Apply limit
        let hasMore = filteredMessages.count > limit
        let limitedMessages = Array(filteredMessages.suffix(limit))

        return ChatMessagePage(
            messages: limitedMessages,
            hasMore: hasMore,
            totalCount: allMessages.count
        )
    }

    public func countMessages(projectId: ProjectID, agentId: AgentID) throws -> Int {
        let allMessages = try findMessages(projectId: projectId, agentId: agentId)
        return allMessages.count
    }

    // MARK: - Private Methods

    /// Get working directory from project ID
    private func getWorkingDirectory(projectId: ProjectID) throws -> String {
        guard let project = try projectRepository.findById(projectId),
              let workingDir = project.workingDirectory else {
            throw ChatFileRepositoryError.workingDirectoryNotSet
        }
        return workingDir
    }

    /// Read messages from file
    private func readMessagesFromFile(at url: URL) throws -> [ChatMessage] {
        // Return empty array if file doesn't exist
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ChatFileRepositoryError.readFailed(url, error)
        }

        // Return empty array if file is empty
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
                // Skip failed lines (log warning but continue)
                print("[ChatFileRepository] Warning: Failed to decode line: \(error)")
            }
        }

        return messages
    }

    /// Append message to file
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

        // Add newline
        jsonString += "\n"

        // Create new file if it doesn't exist
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try jsonString.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw ChatFileRepositoryError.writeFailed(url, error)
            }
            return
        }

        // Append to existing file
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
