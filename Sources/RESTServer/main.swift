// Sources/RESTServer/main.swift
// AI Agent PM - REST API Server Entry Point

import Foundation
import Infrastructure

// Helper function using MCPLogger
func log(_ message: String) {
    MCPLogger.shared.info("[rest-server] \(message)", category: .system)
}

// Initialize logger outputs for REST server
private func setupLogger() {
    let logger = MCPLogger.shared
    let logDirectory = AppConfig.appSupportDirectory.path

    // 既存ログファイルの移行（日付なしファイル → 日付付きファイル）
    let migrator = LogMigrator(directory: logDirectory)
    migrator.migrateIfNeeded(prefix: "rest-server")

    // ファイル出力を設定（日付別ローテーション、JSON形式）
    logger.addOutput(RotatingFileLogOutput(directory: logDirectory, prefix: "rest-server", format: .json))
    logger.addOutput(StderrLogOutput())
}
setupLogger()

let dbPath = AppConfig.databasePath

// Debug logging (stderr to avoid buffering)
let envDbPath = ProcessInfo.processInfo.environment["AIAGENTPM_DB_PATH"] ?? "(not set)"
let envWebUIPath = ProcessInfo.processInfo.environment["AIAGENTPM_WEBUI_PATH"] ?? "(not set)"
let envPort = ProcessInfo.processInfo.environment[AppConfig.WebServer.portEnvKey] ?? "(not set)"
log("AIAGENTPM_DB_PATH env = \(envDbPath)")
log("AIAGENTPM_WEBUI_PATH env = \(envWebUIPath)")
log("\(AppConfig.WebServer.portEnvKey) env = \(envPort)")
log("Using database: \(dbPath)")

// Get port from environment or use default
let port = AppConfig.WebServer.port

// Verify database exists
guard FileManager.default.fileExists(atPath: dbPath) else {
    log("Error: Database not found at \(dbPath)")
    log("Please run the macOS app or MCP server first to initialize the database.")
    exit(1)
}

// Get web-ui path from environment (optional)
let webUIPath: String?
if let path = ProcessInfo.processInfo.environment["AIAGENTPM_WEBUI_PATH"],
   FileManager.default.fileExists(atPath: path) {
    webUIPath = path
    log("Static files will be served from: \(path)")
} else {
    webUIPath = nil
    log("Static file serving disabled (no AIAGENTPM_WEBUI_PATH or path not found)")
}

let database = try DatabaseSetup.createDatabase(at: dbPath)
let server = RESTServer(database: database, port: port, webUIPath: webUIPath)

log("Starting REST API server on port \(port)...")

// Run the async server using _Concurrency.Task to avoid conflict with Domain.Task
let semaphore = DispatchSemaphore(value: 0)
_Concurrency.Task {
    do {
        try await server.run()
    } catch {
        log("Server error: \(error)")
        exit(1)
    }
    semaphore.signal()
}
semaphore.wait()
