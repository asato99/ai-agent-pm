// Sources/App/Core/Services/MCPDaemonManager.swift
// MCP Daemon lifecycle management
// Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md

import Foundation
import Infrastructure

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
        // First check if bundled with the app
        if let bundledPath = Bundle.main.path(forResource: "mcp-server-pm", ofType: nil) {
            return bundledPath
        }

        // Fallback: Check alongside the app bundle (for development)
        if let execURL = Bundle.main.executableURL {
            let devPath = execURL
                .deletingLastPathComponent()
                .appendingPathComponent("mcp-server-pm")
                .path
            if FileManager.default.fileExists(atPath: devPath) {
                return devPath
            }
        }

        // Fallback: Use swift build output (for development)
        // Path: Sources/App/Core/Services/MCPDaemonManager.swift
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // MCPDaemonManager.swift → Services
            .deletingLastPathComponent()  // Services → Core
            .deletingLastPathComponent()  // Core → App
            .deletingLastPathComponent()  // App → Sources
            .deletingLastPathComponent()  // Sources → project root
        let buildPath = projectRoot.appendingPathComponent(".build/debug/mcp-server-pm").path
        if FileManager.default.fileExists(atPath: buildPath) {
            return buildPath
        }

        // Final fallback
        return "/usr/local/bin/mcp-server-pm"
    }

    // MARK: - Initialization

    public init() {
        // Skip timers during UI testing to avoid interfering with XCUITest accessibility queries
        self.skipTimers = CommandLine.arguments.contains("-UITesting")
        // Check if daemon is already running (from previous session or external start)
        checkExistingDaemon()
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
        guard status == .stopped || status.isError else {
            if status == .running {
                throw DaemonError.alreadyRunning
            }
            return
        }

        status = .starting

        do {
            // Ensure app support directory exists
            try FileManager.default.createDirectory(
                at: AppConfig.appSupportDirectory,
                withIntermediateDirectories: true
            )

            // Clean up stale socket if exists
            if FileManager.default.fileExists(atPath: socketPath) {
                try FileManager.default.removeItem(atPath: socketPath)
            }

            // Verify executable exists
            guard FileManager.default.fileExists(atPath: executablePath) else {
                status = .error("Executable not found")
                throw DaemonError.executableNotFound
            }

            // Launch daemon process (without --foreground so it forks and survives app termination)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["daemon"]  // No --foreground: daemon forks and runs independently
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            // Set working directory to app support
            process.currentDirectoryURL = AppConfig.appSupportDirectory

            // Set environment variables for daemon process
            // Copy current environment and add AIAGENTPM_DB_PATH if specified
            var environment = ProcessInfo.processInfo.environment
            if let databasePath = databasePath {
                environment["AIAGENTPM_DB_PATH"] = databasePath
                NSLog("[MCPDaemonManager] Setting AIAGENTPM_DB_PATH=\(databasePath)")
            }
            process.environment = environment

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

            NSLog("[MCPDaemonManager] Daemon started successfully (PID: \(process.processIdentifier), skipTimers: \(skipTimers))")

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
    /// Sends SIGTERM to the daemon process and waits for it to exit.
    /// Cleans up the socket and PID files.
    public func stop() async {
        guard status == .running || status == .starting else { return }

        status = .stopping

        // Stop timers and monitors
        stopUptimeTimer()
        stopLogMonitor()

        // Try to read PID and send SIGTERM
        if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
           let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
            NSLog("[MCPDaemonManager] Sent SIGTERM to PID \(pid)")
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

        startTime = nil
        uptime = 0
        status = .stopped

        NSLog("[MCPDaemonManager] Daemon stopped")
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
        // Check if PID file exists and process is running
        guard FileManager.default.fileExists(atPath: pidPath),
              let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
              let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            status = .stopped
            return
        }

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
                NSLog("[MCPDaemonManager] Found existing daemon (PID: \(pid), skipTimers: \(skipTimers))")
            } else {
                // Process running but socket missing - daemon is broken, kill it
                NSLog("[MCPDaemonManager] Daemon process exists (PID: \(pid)) but socket missing - terminating broken daemon")
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
            NSLog("[MCPDaemonManager] Cleaned up stale PID file")
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
