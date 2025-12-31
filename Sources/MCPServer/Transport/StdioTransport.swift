// Sources/MCPServer/Transport/StdioTransport.swift
// 参照: docs/architecture/MCP_SERVER.md - stdio通信

import Foundation

/// stdio経由でのJSON-RPC通信を管理
/// MCPプロトコルはContent-Lengthヘッダーベースのメッセージ形式を使用
final class StdioTransport {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput
    private let errorOutput = FileHandle.standardError

    /// メッセージを読み取る
    /// Content-Lengthヘッダー形式とJSON Lines形式の両方をサポート
    func readMessage() throws -> JSONRPCRequest {
        let firstLine = try readLine()

        // Content-Lengthヘッダーで始まる場合はヘッダー形式
        if firstLine.hasPrefix("Content-Length:") {
            let contentLength = try parseContentLength(from: firstLine)

            // 空行をスキップ
            _ = try readLine()

            // ボディを読み取る
            let bodyData = input.readData(ofLength: contentLength)
            guard bodyData.count == contentLength else {
                throw TransportError.incompleteRead
            }

            return try decodeRequest(from: bodyData)
        }

        // JSON Lines形式（ヘッダーなし）
        guard let lineData = firstLine.data(using: .utf8) else {
            throw TransportError.invalidHeader(firstLine)
        }

        return try decodeRequest(from: lineData)
    }

    /// Content-Lengthヘッダーをパース
    private func parseContentLength(from line: String) throws -> Int {
        let prefix = "Content-Length:"
        guard line.hasPrefix(prefix) else {
            throw TransportError.invalidHeader(line)
        }

        let lengthString = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let length = Int(lengthString) else {
            throw TransportError.invalidContentLength(String(lengthString))
        }

        return length
    }

    /// JSONリクエストをデコード
    private func decodeRequest(from data: Data) throws -> JSONRPCRequest {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            log("JSON decode error: \(error)")
            throw TransportError.invalidJSON(error)
        }
    }

    /// メッセージを書き込む（JSON Lines形式）
    func writeMessage(_ response: JSONRPCResponse) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var data = try encoder.encode(response)
        // 改行を追加してJSON Lines形式に
        data.append(contentsOf: "\n".utf8)

        output.write(data)

        // stdoutをフラッシュして即座に送信
        if #available(macOS 10.15.4, *) {
            try? output.synchronize()
        }
    }

    /// エラーログを出力（stderrへ）
    func log(_ message: String) {
        let logMessage = "[mcp-server-pm] \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            errorOutput.write(data)
        }
    }

    // MARK: - Private

    /// 1行を読み取る（\r\nまたは\nで終端）
    private func readLine() throws -> String {
        var line = ""
        while true {
            let data = input.readData(ofLength: 1)
            guard let byte = data.first else {
                if line.isEmpty {
                    throw TransportError.endOfInput
                }
                break
            }

            let char = Character(UnicodeScalar(byte))
            if char == "\n" {
                break
            }
            if char != "\r" {
                line.append(char)
            }
        }
        return line
    }
}

// MARK: - TransportError

enum TransportError: Error, CustomStringConvertible {
    case invalidHeader(String)
    case invalidContentLength(String)
    case incompleteRead
    case endOfInput
    case invalidJSON(Error)
    case encodingFailed

    var description: String {
        switch self {
        case .invalidHeader(let header):
            return "Invalid header: \(header)"
        case .invalidContentLength(let value):
            return "Invalid Content-Length: \(value)"
        case .incompleteRead:
            return "Incomplete read"
        case .endOfInput:
            return "End of input"
        case .invalidJSON(let error):
            return "Invalid JSON: \(error)"
        case .encodingFailed:
            return "Encoding failed"
        }
    }
}
