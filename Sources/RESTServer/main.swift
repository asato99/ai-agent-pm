// Sources/RESTServer/main.swift
// AI Agent PM - REST API Server Entry Point

import Foundation
import Infrastructure

let dbPath = AppConfig.databasePath

// Debug logging
let envDbPath = ProcessInfo.processInfo.environment["AIAGENTPM_DB_PATH"] ?? "(not set)"
let envWebUIPath = ProcessInfo.processInfo.environment["AIAGENTPM_WEBUI_PATH"] ?? "(not set)"
print("[rest-server-pm] AIAGENTPM_DB_PATH env = \(envDbPath)")
print("[rest-server-pm] AIAGENTPM_WEBUI_PATH env = \(envWebUIPath)")
print("[rest-server-pm] Using database: \(dbPath)")

// Verify database exists
guard FileManager.default.fileExists(atPath: dbPath) else {
    print("[rest-server-pm] Error: Database not found at \(dbPath)")
    print("[rest-server-pm] Please run the macOS app or MCP server first to initialize the database.")
    exit(1)
}

// Get web-ui path from environment (optional)
let webUIPath: String?
if let path = ProcessInfo.processInfo.environment["AIAGENTPM_WEBUI_PATH"],
   FileManager.default.fileExists(atPath: path) {
    webUIPath = path
    print("[rest-server-pm] Static files will be served from: \(path)")
} else {
    webUIPath = nil
    print("[rest-server-pm] Static file serving disabled (no AIAGENTPM_WEBUI_PATH or path not found)")
}

let database = try DatabaseSetup.createDatabase(at: dbPath)
let server = RESTServer(database: database, webUIPath: webUIPath)

print("[rest-server-pm] Starting REST API server on port 8080...")

// Run the async server using _Concurrency.Task to avoid conflict with Domain.Task
let semaphore = DispatchSemaphore(value: 0)
_Concurrency.Task {
    do {
        try await server.run()
    } catch {
        print("[rest-server-pm] Server error: \(error)")
        exit(1)
    }
    semaphore.signal()
}
semaphore.wait()
