// Sources/App/Core/Services/MCPDaemonManager.swift
// MCP Daemon lifecycle management
// Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md

import Foundation
import Infrastructure

// MARK: - Debug Logging using MCPLogger
private func debugLog(_ message: String) {
    // MCPLoggerを使用してログ出力（system カテゴリ）
    MCPLogger.shared.debug("[MCPDaemonManager] \(message)", category: .system)

    // XCUITest用に/tmpファイルにも出力（デバッグ用）
    let logFile = "/tmp/aiagentpm_debug.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] [MCPDaemonManager] \(message)\n"
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

/// Daemon running status
public enum DaemonStatus: Equatable {
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

/// Errors that can occur during daemon management
public enum DaemonError: LocalizedError {
    case socketNotCreated
    case executableNotFound
    case alreadyRunning
    case processLaunchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .socketNotCreated:
            return "Failed to start daemon: socket not created within timeout"
        case .executableNotFound:
            return "mcp-server-pm executable not found"
        case .alreadyRunning:
            return "Daemon is already running"
        case .processLaunchFailed(let reason):
            return "Failed to launch daemon process: \(reason)"
        }
    }
}

/// Manages the MCP daemon process lifecycle
///
/// The MCPDaemonManager handles starting, stopping, and monitoring the
/// mcp-server-pm daemon process. It provides real-time status updates
/// and uptime tracking.
///
/// Usage:
/// - Auto-start on app launch via AppDelegate
/// - Manual control via MCPServerView in sidebar
@MainActor
public final class MCPDaemonManager: ObservableObject {

    // MARK: - Published State

    /// Current daemon status
    @Published public private(set) var status: DaemonStatus = .stopped

    /// Uptime in seconds since daemon started
    @Published public private(set) var uptime: TimeInterval = 0

    /// Last N lines from the log file
    @Published public private(set) var lastLogLines: [String] = []

    // MARK: - Private Properties

    private var daemonProcess: Process?
    private var uptimeTimer: Timer?
    private var startTime: Date?
    private var logMonitorTask: Task<Void, Never>?

    /// Whether to skip timers (for UI testing to avoid accessibility interference)
    private let skipTimers: Bool

    /// Optional closure to get coordinator token from database
    /// Set by DependencyContainer after initialization
    public var coordinatorTokenProvider: (() -> String?)?

    // MARK: - Path Properties

    /// Unix socket path
    public var socketPath: String {
        AppConfig.appSupportDirectory.appendingPathComponent("mcp.sock").path
    }

    /// PID file path
    public var pidPath: String {
        AppConfig.appSupportDirectory.appendingPathComponent("daemon.pid").path
    }

    /// Log file path
    public var logPath: String {
        AppConfig.appSupportDirectory.appendingPathComponent("mcp-daemon.log").path
    }

    /// Path to mcp-server-pm executable
    private var executablePath: String {
        // First check if bundled with the app (in Contents/MacOS/)
        if let execURL = Bundle.main.executableURL {
            let bundledPath = execURL
                .deletingLastPathComponent()  // Remove app executable name
                .appendingPathComponent("mcp-server-pm")
                .path
            debugLog(" Checking bundled path: \(bundledPath)")
            if FileManager.default.fileExists(atPath: bundledPath) {
                debugLog(" Found bundled executable: \(bundledPath)")
                return bundledPath
            }
        }

        // Fallback: Check in the same Products/Debug directory as the app bundle (for Xcode development)
        // App path: .../DerivedData/.../Build/Products/Debug/AIAgentPM.app/Contents/MacOS/AIAgentPM
        // MCPServer path: .../DerivedData/.../Build/Products/Debug/mcp-server-pm
        if let execURL = Bundle.main.executableURL {
            let devPath = execURL
                .deletingLastPathComponent()  // AIAgentPM → MacOS
                .deletingLastPathComponent()  // MacOS → Contents
                .deletingLastPathComponent()  // Contents → AIAgentPM.app
                .deletingLastPathComponent()  // AIAgentPM.app → Debug
                .appendingPathComponent("mcp-server-pm")
                .path
            debugLog(" Checking dev path: \(devPath)")
            if FileManager.default.fileExists(atPath: devPath) {
                debugLog(" Found executable at dev path")
                return devPath
            }
        }

        // Final fallback
        debugLog(" No executable found, using fallback: /usr/local/bin/mcp-server-pm")
        return "/usr/local/bin/mcp-server-pm"
    }

    // MARK: - Initialization

    public init() {
        debugLog("init() called, UITesting: \(CommandLine.arguments.contains("-UITesting"))")
        // Skip timers during UI testing to avoid interfering with XCUITest accessibility queries
        self.skipTimers = CommandLine.arguments.contains("-UITesting")
        // Check if daemon is already running (from previous session or external start)
        checkExistingDaemon()
        debugLog("init() completed, status: \(status)")
    }

    // MARK: - Public Methods

    /// Start the daemon process
    ///
    /// Launches the mcp-server-pm daemon in foreground mode and waits
    /// for the Unix socket to be created.
    ///
    /// - Parameter databasePath: Optional database path. If provided, sets AIAGENTPM_DB_PATH
    ///   environment variable for the daemon process. Used during UITest to ensure
    ///   the daemon uses the same sandboxed database as the app.
    /// - Throws: DaemonError if startup fails
    public func start(databasePath: String? = nil) async throws {
        debugLog(" start() called, current status: \(status), databasePath: \(databasePath ?? "nil")")

        guard status == .stopped || status.isError else {
            if status == .running {
                debugLog(" start() - already running, throwing error")
                throw DaemonError.alreadyRunning
            }
            debugLog(" start() - status is \(status), returning early")
            return
        }

        status = .starting

        do {
            // Ensure app support directory exists
            try FileManager.default.createDirectory(
                at: AppConfig.appSupportDirectory,
                withIntermediateDirectories: true
            )
            debugLog(" App support directory ensured: \(AppConfig.appSupportDirectory.path)")

            // Clean up stale socket if exists
            if FileManager.default.fileExists(atPath: socketPath) {
                try FileManager.default.removeItem(atPath: socketPath)
                debugLog(" Removed stale socket at: \(socketPath)")
            }

            // Verify executable exists
            let execPath = executablePath  // Force evaluation and logging
            debugLog(" Executable path resolved to: \(execPath)")
            guard FileManager.default.fileExists(atPath: execPath) else {
                debugLog(" ERROR: Executable not found at \(execPath)")
                status = .error("Executable not found")
                throw DaemonError.executableNotFound
            }
            debugLog(" Executable found at: \(execPath)")

            // Launch daemon process directly with minimal environment
            let process = Process()
            process.executableURL = URL(fileURLWithPath: execPath)
            process.arguments = ["daemon"]

            // Redirect all standard I/O to prevent blocking
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            let stderrPath = "/tmp/mcp_daemon_stderr.log"
            FileManager.default.createFile(atPath: stderrPath, contents: nil, attributes: nil)
            process.standardError = FileHandle(forWritingAtPath: stderrPath) ?? FileHandle.nullDevice

            // Set working directory to app support
            process.currentDirectoryURL = AppConfig.appSupportDirectory

            // Set minimal environment variables
            var environment: [String: String] = [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
                "HOME": NSHomeDirectory(),
                "TMPDIR": NSTemporaryDirectory()
            ]

            // When running from DerivedData, set DYLD_FRAMEWORK_PATH to find frameworks
            // (frameworks are in the same directory as the binary, not in a subdirectory)
            let daemonDir = URL(fileURLWithPath: execPath).deletingLastPathComponent().path
            if daemonDir.contains("DerivedData") {
                environment["DYLD_FRAMEWORK_PATH"] = daemonDir
                debugLog(" Setting DYLD_FRAMEWORK_PATH=\(daemonDir)")
            }
            if let databasePath = databasePath {
                environment["AIAGENTPM_DB_PATH"] = databasePath
                debugLog(" Setting AIAGENTPM_DB_PATH=\(databasePath)")
            }
            // Pass coordinator token if available (for Phase 5 authorization)
            // Priority: 1. Database (via provider), 2. Environment variable
            var coordinatorToken: String?
            if let provider = coordinatorTokenProvider {
                coordinatorToken = provider()
                if coordinatorToken != nil {
                    debugLog(" Got MCP_COORDINATOR_TOKEN from database")
                }
            }
            // Fallback to environment variable for backwards compatibility
            if coordinatorToken == nil {
                coordinatorToken = ProcessInfo.processInfo.environment["MCP_COORDINATOR_TOKEN"]
                if coordinatorToken != nil {
                    debugLog(" Got MCP_COORDINATOR_TOKEN from environment")
                }
            }
            if let token = coordinatorToken {
                environment["MCP_COORDINATOR_TOKEN"] = token
                debugLog(" Setting MCP_COORDINATOR_TOKEN")
            }
            process.environment = environment
            debugLog(" Using minimal environment: \(environment.keys.sorted())")
            debugLog(" Launching daemon from: \(execPath)")

            try process.run()
            // The process forks, so daemonProcess will exit quickly
            // The actual daemon PID is written to pidPath
            daemonProcess = process

            // Wait for socket to be created
            try await waitForSocket(timeout: 10.0)

            startTime = Date()
            status = .running

            // Skip timers during UI testing to avoid XCUITest accessibility issues
            if !skipTimers {
                startUptimeTimer()
                startLogMonitor()
            }

            debugLog(" Daemon started successfully (PID: \(process.processIdentifier), skipTimers: \(skipTimers))")

        } catch let error as DaemonError {
            status = .error(error.localizedDescription)
            throw error
        } catch {
            status = .error(error.localizedDescription)
            throw DaemonError.processLaunchFailed(error.localizedDescription)
        }
    }

    /// Stop the daemon process
    ///
    /// Stops the launchd job and cleans up files.
    public func stop() async {
        guard status == .running || status == .starting else { return }

        status = .stopping

        // Stop timers and monitors
        stopUptimeTimer()
        stopLogMonitor()

        // Try to stop via launchctl first (if launched via launchd)
        let jobLabel = "com.aiagentpm.mcp-daemon"
        let plistPath = "/tmp/\(jobLabel).plist"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "launchctl bootout gui/\(getuid())/\(jobLabel) 2>/dev/null || true"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        debugLog(" Sent launchctl bootout")

        // Also try to read PID and send SIGTERM (fallback for PID-based processes)
        if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
           let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
            debugLog(" Sent SIGTERM to PID \(pid)")
        }

        // Also terminate our managed process if we have one
        if let process = daemonProcess {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            daemonProcess = nil
        }

        // Wait a moment for cleanup
        try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

        // Clean up files
        try? FileManager.default.removeItem(atPath: socketPath)
        try? FileManager.default.removeItem(atPath: pidPath)
        try? FileManager.default.removeItem(atPath: plistPath)

        startTime = nil
        uptime = 0
        status = .stopped

        debugLog(" Daemon stopped")
    }

    /// Restart the daemon
    ///
    /// Stops the daemon if running, then starts it again.
    ///
    /// - Throws: DaemonError if restart fails
    public func restart() async throws {
        await stop()
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        try await start()
    }

    /// Refresh log lines from file
    public func refreshLogs() {
        loadLogLines()
    }

    // MARK: - Private Methods

    /// Check if daemon is already running from a previous session
    private func checkExistingDaemon() {
        debugLog(" checkExistingDaemon called, pidPath: \(pidPath)")

        // Check if PID file exists and process is running
        guard FileManager.default.fileExists(atPath: pidPath),
              let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
              let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            debugLog(" No valid PID file found, status = stopped")
            status = .stopped
            return
        }
        debugLog(" Found PID file with PID: \(pid)")

        // Check if process exists (signal 0 doesn't kill, just checks)
        if kill(pid, 0) == 0 {
            // Process is running - but also verify socket exists
            // If socket doesn't exist, the daemon is in a broken state
            if FileManager.default.fileExists(atPath: socketPath) {
                // Daemon is fully functional
                status = .running
                startTime = Date()  // Approximate start time
                // Skip timers during UI testing to avoid XCUITest accessibility issues
                if !skipTimers {
                    startUptimeTimer()
                    startLogMonitor()
                }
                debugLog(" Found existing daemon (PID: \(pid), skipTimers: \(skipTimers))")
            } else {
                // Process running but socket missing - daemon is broken, kill it
                debugLog(" Daemon process exists (PID: \(pid)) but socket missing - terminating broken daemon")
                kill(pid, SIGTERM)
                // Wait briefly for process to die
                usleep(500_000)  // 500ms
                // Clean up files
                try? FileManager.default.removeItem(atPath: pidPath)
                status = .stopped
            }
        } else {
            // Stale PID file - clean up
            try? FileManager.default.removeItem(atPath: pidPath)
            try? FileManager.default.removeItem(atPath: socketPath)
            status = .stopped
            debugLog(" Cleaned up stale PID file")
        }
    }

    /// Wait for the Unix socket to be created
    private func waitForSocket(timeout: TimeInterval) async throws {
        let startWait = Date()
        let checkInterval: UInt64 = 100_000_000  // 100ms

        while Date().timeIntervalSince(startWait) < timeout {
            if FileManager.default.fileExists(atPath: socketPath) {
                return
            }

            // Check if process died
            if let process = daemonProcess, !process.isRunning {
                throw DaemonError.processLaunchFailed("Process exited with code \(process.terminationStatus)")
            }

            try await Task.sleep(nanoseconds: checkInterval)
        }

        throw DaemonError.socketNotCreated
    }

    /// Start the uptime tracking timer
    private func startUptimeTimer() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                if let startTime = self?.startTime {
                    self?.uptime = Date().timeIntervalSince(startTime)
                }
            }
        }
    }

    /// Stop the uptime tracking timer
    private func stopUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }

    /// Start monitoring the log file
    private func startLogMonitor() {
        logMonitorTask = Task { [weak self] in
            await self?.monitorLogFile()
        }
    }

    /// Stop monitoring the log file
    private func stopLogMonitor() {
        logMonitorTask?.cancel()
        logMonitorTask = nil
    }

    /// Monitor the log file for changes
    private func monitorLogFile() async {
        while !Task.isCancelled {
            loadLogLines()
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
        }
    }

    /// Load the last N lines from the log file
    private func loadLogLines() {
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return
        }

        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        Task { @MainActor [weak self] in
            self?.lastLogLines = Array(lines.suffix(200))  // Keep last 200 lines
        }
    }
}
