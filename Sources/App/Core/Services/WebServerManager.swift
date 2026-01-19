// Sources/App/Core/Services/WebServerManager.swift
// Web Server lifecycle management for REST API and web-ui static files

import Foundation
import Infrastructure

// MARK: - Debug Logging

private func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] [WebServerManager] \(message)\n"

    NSLog("[WebServerManager] %@", message)

    // Write to file for debugging
    let logFile = "/tmp/aiagentpm_webserver_debug.log"
    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data, attributes: nil)
        }
    }
}

/// Web server running status
public enum WebServerStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case error(String)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

/// Errors that can occur during web server management
public enum WebServerError: LocalizedError {
    case portNotListening
    case executableNotFound
    case alreadyRunning
    case processLaunchFailed(String)
    case databaseNotFound

    public var errorDescription: String? {
        switch self {
        case .portNotListening:
            return "Failed to start web server: port not listening within timeout"
        case .executableNotFound:
            return "rest-server-pm executable not found"
        case .alreadyRunning:
            return "Web server is already running"
        case .processLaunchFailed(let reason):
            return "Failed to launch web server process: \(reason)"
        case .databaseNotFound:
            return "Database not found. Please ensure the app has been initialized."
        }
    }
}

/// Manages the Web Server process lifecycle
///
/// The WebServerManager handles starting, stopping, and monitoring the
/// REST API server with static file serving. It provides real-time status
/// updates and uptime tracking.
///
/// Usage:
/// - Auto-start on app launch via AppDelegate
/// - Manual control via WebServerView in sidebar
@MainActor
public final class WebServerManager: ObservableObject {

    // MARK: - Published State

    /// Current server status
    @Published public private(set) var status: WebServerStatus = .stopped

    /// Uptime in seconds since server started
    @Published public private(set) var uptime: TimeInterval = 0

    /// Last N lines from the log file
    @Published public private(set) var lastLogLines: [String] = []

    // MARK: - Private Properties

    private var serverProcess: Process?
    private var uptimeTimer: Timer?
    private var startTime: Date?
    private var logMonitorTask: Task<Void, Never>?

    /// Whether to skip timers (for UI testing)
    private let skipTimers: Bool

    /// Server port
    public let port: Int = 8080

    // MARK: - Path Properties

    /// PID file path
    public var pidPath: String {
        AppConfig.appSupportDirectory.appendingPathComponent("webserver.pid").path
    }

    /// Log file path
    public var logPath: String {
        AppConfig.appSupportDirectory.appendingPathComponent("webserver.log").path
    }

    /// Web UI static files directory
    public var webUIPath: String {
        // Check bundled resources first
        if let bundledPath = Bundle.main.resourceURL?.appendingPathComponent("web-ui").path,
           FileManager.default.fileExists(atPath: bundledPath) {
            return bundledPath
        }
        // Fallback to app support directory
        return AppConfig.appSupportDirectory.appendingPathComponent("web-ui").path
    }

    /// Path to rest-server-pm executable
    private var executablePath: String {
        // First check if bundled with the app
        if let bundledPath = Bundle.main.path(forResource: "rest-server-pm", ofType: nil) {
            debugLog("Found bundled executable: \(bundledPath)")
            return bundledPath
        }

        // Fallback: Check in the same Products/Debug directory as the app bundle
        if let execURL = Bundle.main.executableURL {
            let devPath = execURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("rest-server-pm")
                .path
            debugLog("Checking dev path: \(devPath)")
            if FileManager.default.fileExists(atPath: devPath) {
                debugLog("Found executable at dev path")
                return devPath
            }
        }

        debugLog("No executable found, using fallback: /usr/local/bin/rest-server-pm")
        return "/usr/local/bin/rest-server-pm"
    }

    // MARK: - Initialization

    public init() {
        debugLog("init() called, UITesting: \(CommandLine.arguments.contains("-UITesting"))")
        self.skipTimers = CommandLine.arguments.contains("-UITesting")
        checkExistingServer()
        debugLog("init() completed, status: \(status)")
    }

    // MARK: - Public Methods

    /// Start the web server process
    ///
    /// Launches the rest-server-pm server and waits for the HTTP port to be listening.
    ///
    /// - Parameter databasePath: Optional database path. If provided, sets AIAGENTPM_DB_PATH
    ///   environment variable for the server process.
    /// - Throws: WebServerError if startup fails
    public func start(databasePath: String? = nil) async throws {
        debugLog("start() called, current status: \(status), databasePath: \(databasePath ?? "nil")")

        guard status == .stopped || status.isError else {
            if status == .running {
                debugLog("start() - already running, throwing error")
                throw WebServerError.alreadyRunning
            }
            debugLog("start() - status is \(status), returning early")
            return
        }

        status = .starting

        do {
            // Ensure app support directory exists
            try FileManager.default.createDirectory(
                at: AppConfig.appSupportDirectory,
                withIntermediateDirectories: true
            )
            debugLog("App support directory ensured: \(AppConfig.appSupportDirectory.path)")

            // Verify executable exists
            let execPath = executablePath
            debugLog("Executable path resolved to: \(execPath)")
            guard FileManager.default.fileExists(atPath: execPath) else {
                debugLog("ERROR: Executable not found at \(execPath)")
                status = .error("Executable not found")
                throw WebServerError.executableNotFound
            }
            debugLog("Executable found at: \(execPath)")

            // Check database path
            let dbPath = databasePath ?? AppConfig.databasePath
            guard FileManager.default.fileExists(atPath: dbPath) else {
                debugLog("ERROR: Database not found at \(dbPath)")
                status = .error("Database not found")
                throw WebServerError.databaseNotFound
            }
            debugLog("Database found at: \(dbPath)")

            // Launch server process
            let process = Process()
            process.executableURL = URL(fileURLWithPath: execPath)
            process.arguments = []

            // Redirect output to log file
            process.standardInput = FileHandle.nullDevice
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            let logHandle = FileHandle(forWritingAtPath: logPath) ?? FileHandle.nullDevice
            process.standardOutput = logHandle
            process.standardError = logHandle

            // Set working directory
            process.currentDirectoryURL = AppConfig.appSupportDirectory

            // Set environment variables
            var environment: [String: String] = [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
                "HOME": NSHomeDirectory(),
                "TMPDIR": NSTemporaryDirectory()
            ]
            environment["AIAGENTPM_DB_PATH"] = dbPath
            debugLog("Setting AIAGENTPM_DB_PATH=\(dbPath)")

            process.environment = environment
            debugLog("Launching web server from: \(execPath)")

            try process.run()
            serverProcess = process

            // Save PID
            try "\(process.processIdentifier)".write(toFile: pidPath, atomically: true, encoding: .utf8)
            debugLog("Saved PID \(process.processIdentifier) to \(pidPath)")

            // Wait for HTTP port to be listening
            try await waitForPort(timeout: 10.0)

            startTime = Date()
            status = .running

            if !skipTimers {
                startUptimeTimer()
                startLogMonitor()
            }

            debugLog("Web server started successfully (PID: \(process.processIdentifier), skipTimers: \(skipTimers))")

        } catch let error as WebServerError {
            status = .error(error.localizedDescription)
            throw error
        } catch {
            status = .error(error.localizedDescription)
            throw WebServerError.processLaunchFailed(error.localizedDescription)
        }
    }

    /// Stop the web server process
    public func stop() async {
        guard status == .running || status == .starting else { return }

        status = .stopping

        stopUptimeTimer()
        stopLogMonitor()

        // Try to read PID and send SIGTERM
        if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
           let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
            debugLog("Sent SIGTERM to PID \(pid)")
        }

        // Also terminate our managed process if we have one
        if let process = serverProcess {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            serverProcess = nil
        }

        // Wait for cleanup
        try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

        // Clean up files
        try? FileManager.default.removeItem(atPath: pidPath)

        startTime = nil
        uptime = 0
        status = .stopped

        debugLog("Web server stopped")
    }

    /// Restart the web server
    public func restart() async throws {
        await stop()
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        try await start()
    }

    /// Refresh log lines from file
    public func refreshLogs() {
        loadLogLines()
    }

    /// Get the server URL
    public var serverURL: String {
        "http://127.0.0.1:\(port)"
    }

    // MARK: - Private Methods

    /// Check if server is already running
    private func checkExistingServer() {
        debugLog("checkExistingServer called, pidPath: \(pidPath)")

        guard FileManager.default.fileExists(atPath: pidPath),
              let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
              let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            debugLog("No valid PID file found, status = stopped")
            status = .stopped
            return
        }
        debugLog("Found PID file with PID: \(pid)")

        // Check if process exists
        if kill(pid, 0) == 0 {
            // Verify port is listening
            if isPortListening() {
                status = .running
                startTime = Date()
                if !skipTimers {
                    startUptimeTimer()
                    startLogMonitor()
                }
                debugLog("Found existing web server (PID: \(pid), skipTimers: \(skipTimers))")
            } else {
                // Process running but port not listening - broken state
                debugLog("Server process exists (PID: \(pid)) but port not listening - terminating")
                kill(pid, SIGTERM)
                usleep(500_000)
                try? FileManager.default.removeItem(atPath: pidPath)
                status = .stopped
            }
        } else {
            // Stale PID file
            try? FileManager.default.removeItem(atPath: pidPath)
            status = .stopped
            debugLog("Cleaned up stale PID file")
        }
    }

    /// Wait for HTTP port to be listening
    private func waitForPort(timeout: TimeInterval) async throws {
        let startWait = Date()
        let checkInterval: UInt64 = 100_000_000  // 100ms

        while Date().timeIntervalSince(startWait) < timeout {
            if isPortListening() {
                return
            }

            // Check if process died
            if let process = serverProcess, !process.isRunning {
                throw WebServerError.processLaunchFailed("Process exited with code \(process.terminationStatus)")
            }

            try await Task.sleep(nanoseconds: checkInterval)
        }

        throw WebServerError.portNotListening
    }

    /// Check if the HTTP port is listening using a simple synchronous connect
    private func isPortListening() -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo("127.0.0.1", "\(port)", &hints, &result)
        guard status == 0, let addrInfo = result else {
            return false
        }
        defer { freeaddrinfo(result) }

        let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Set a connect timeout using SO_SNDTIMEO
        var timeout = timeval(tv_sec: 0, tv_usec: 100_000)  // 100ms
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let connectResult = connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)
        return connectResult == 0
    }

    private func startUptimeTimer() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                if let startTime = self?.startTime {
                    self?.uptime = Date().timeIntervalSince(startTime)
                }
            }
        }
    }

    private func stopUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }

    private func startLogMonitor() {
        logMonitorTask = Task { [weak self] in
            await self?.monitorLogFile()
        }
    }

    private func stopLogMonitor() {
        logMonitorTask?.cancel()
        logMonitorTask = nil
    }

    private func monitorLogFile() async {
        while !Task.isCancelled {
            loadLogLines()
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
        }
    }

    private func loadLogLines() {
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return
        }

        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        Task { @MainActor [weak self] in
            self?.lastLogLines = Array(lines.suffix(200))
        }
    }
}
