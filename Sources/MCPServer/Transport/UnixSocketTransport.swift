// Sources/MCPServer/Transport/UnixSocketTransport.swift
// Unix Socketを使用したJSON-RPC通信（Runner用デーモンモード）
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md

import Foundation
import Infrastructure

/// Unix Socket経由でのJSON-RPC通信を管理
/// Runner（外部プロセス）からの接続を受け付けるデーモンモード用
final class UnixSocketServer {
    private let socketPath: String
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private let database: DatabaseQueue
    private let logPath: String

    init(socketPath: String? = nil, database: DatabaseQueue) {
        self.socketPath = socketPath ?? Self.defaultSocketPath()
        self.database = database
        self.logPath = AppConfig.appSupportDirectory.appendingPathComponent("mcp-daemon.log").path
    }

    static func defaultSocketPath() -> String {
        return AppConfig.appSupportDirectory.appendingPathComponent("mcp.sock").path
    }

    /// デーモンを起動
    func start() throws {
        log("Starting Unix socket server at: \(socketPath)")

        // 既存のソケットファイルを削除
        if FileManager.default.fileExists(atPath: socketPath) {
            try FileManager.default.removeItem(atPath: socketPath)
            log("Removed existing socket file")
        }

        // ソケットディレクトリを作成
        let socketDir = (socketPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: socketDir) {
            try FileManager.default.createDirectory(
                atPath: socketDir,
                withIntermediateDirectories: true
            )
        }

        // Unix domain socketを作成
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw SocketError.createFailed(errno)
        }

        // ソケットアドレスを設定
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // パスをコピー（sun_pathは固定長配列）
        socketPath.withCString { pathPtr in
            let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
            _ = withUnsafeMutableBytes(of: &addr.sun_path) { sunPathPtr in
                strncpy(sunPathPtr.baseAddress!.assumingMemoryBound(to: CChar.self), pathPtr, maxLen)
            }
        }

        // バインド
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            close(serverSocket)
            throw SocketError.bindFailed(errno)
        }

        // リッスン開始
        guard listen(serverSocket, 5) == 0 else {
            close(serverSocket)
            throw SocketError.listenFailed(errno)
        }

        isRunning = true
        log("Server listening on: \(socketPath)")

        // SIGINTとSIGTERMをハンドリング
        signal(SIGINT) { _ in
            // シグナルハンドラ内では最小限の処理
        }
        signal(SIGTERM) { _ in
            // シグナルハンドラ内では最小限の処理
        }

        // 接続受付ループ
        while isRunning {
            let clientSocket = accept(serverSocket, nil, nil)
            if clientSocket < 0 {
                if errno == EINTR {
                    // シグナル割り込み - 終了チェック
                    continue
                }
                log("Accept failed: \(errno)")
                continue
            }

            log("Client connected")

            // クライアント処理（同期的に1つずつ）
            handleClient(socket: clientSocket)
        }

        cleanup()
    }

    /// クライアント接続を処理
    private func handleClient(socket clientSocket: Int32) {
        defer {
            close(clientSocket)
            log("Client disconnected")
        }

        let transport = UnixSocketTransport(socket: clientSocket, logHandler: { [weak self] msg in
            self?.log(msg)
        })
        let server = MCPServer(database: database, transport: transport)

        do {
            try server.runOnce()
        } catch {
            log("Client error: \(error)")
        }
    }

    /// サーバーを停止
    func stop() {
        log("Stopping server...")
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        cleanup()
    }

    private func cleanup() {
        // ソケットファイルを削除
        try? FileManager.default.removeItem(atPath: socketPath)
        log("Server stopped")
    }

    /// ログ出力
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] [daemon] \(message)\n"

        // stderrに出力
        FileHandle.standardError.write(logLine.data(using: .utf8)!)

        // ファイルにも出力
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(logLine.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: logLine.data(using: .utf8))
        }
    }
}

/// Unix Socket経由での単一クライアント通信
final class UnixSocketTransport: MCPTransport {
    private let socket: Int32
    private var buffer = Data()
    private let logHandler: (String) -> Void

    init(socket: Int32, logHandler: @escaping (String) -> Void) {
        self.socket = socket
        self.logHandler = logHandler
    }

    func readMessage() throws -> JSONRPCRequest {
        // 改行までデータを読み取る（JSON Lines形式）
        while true {
            // バッファ内に改行があるかチェック
            if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.prefix(upTo: newlineIndex)
                buffer = buffer.suffix(from: buffer.index(after: newlineIndex))

                guard !lineData.isEmpty else {
                    continue
                }

                return try decodeRequest(from: Data(lineData))
            }

            // ソケットから読み取り
            var readBuffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(socket, &readBuffer, readBuffer.count)

            if bytesRead < 0 {
                throw TransportError.endOfInput
            }
            if bytesRead == 0 {
                throw TransportError.endOfInput
            }

            buffer.append(contentsOf: readBuffer.prefix(bytesRead))
        }
    }

    private func decodeRequest(from data: Data) throws -> JSONRPCRequest {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            log("JSON decode error: \(error)")
            throw TransportError.invalidJSON(error)
        }
    }

    func writeMessage(_ response: JSONRPCResponse) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var data = try encoder.encode(response)
        data.append(contentsOf: "\n".utf8)

        _ = data.withUnsafeBytes { buffer in
            write(socket, buffer.baseAddress!, buffer.count)
        }
    }

    func log(_ message: String) {
        logHandler(message)
    }
}

// MARK: - SocketError

enum SocketError: Error, CustomStringConvertible {
    case createFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case acceptFailed(Int32)
    case readFailed(Int32)
    case writeFailed(Int32)

    var description: String {
        switch self {
        case .createFailed(let errno):
            return "Failed to create socket: \(String(cString: strerror(errno)))"
        case .bindFailed(let errno):
            return "Failed to bind socket: \(String(cString: strerror(errno)))"
        case .listenFailed(let errno):
            return "Failed to listen on socket: \(String(cString: strerror(errno)))"
        case .acceptFailed(let errno):
            return "Failed to accept connection: \(String(cString: strerror(errno)))"
        case .readFailed(let errno):
            return "Failed to read from socket: \(String(cString: strerror(errno)))"
        case .writeFailed(let errno):
            return "Failed to write to socket: \(String(cString: strerror(errno)))"
        }
    }
}

// MARK: - GRDB DatabaseQueue type alias

import GRDB
typealias DatabaseQueue = GRDB.DatabaseQueue
