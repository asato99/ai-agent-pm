// Sources/Infrastructure/Services/ClaudeCodeKickService.swift
// Claude Code CLI起動サービスの実装
// 参照: docs/requirements/AGENTS.md - 活動のキック

import Foundation
import Domain

/// Claude Code CLIを起動するサービス
public final class ClaudeCodeKickService: AgentKickServiceProtocol, @unchecked Sendable {
    private let shouldSimulate: Bool
    private let mcpServerPath: String?

    public init(mcpServerPath: String? = nil) {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        // ENABLE_REAL_KICK=1 または -EnableRealKick 引数が設定されていれば、UIテスト中でも実際のキックを行う
        let enableRealKickEnv = ProcessInfo.processInfo.environment["ENABLE_REAL_KICK"] == "1"
        let enableRealKickArg = ProcessInfo.processInfo.arguments.contains("-EnableRealKick")
        let enableRealKick = enableRealKickEnv || enableRealKickArg

        self.shouldSimulate = isUITesting && !enableRealKick
        self.mcpServerPath = mcpServerPath
    }

    public func kick(
        agent: Agent,
        task: Task,
        project: Project
    ) async throws -> AgentKickResult {
        // 作業ディレクトリの確認
        guard let workingDirectory = project.workingDirectory, !workingDirectory.isEmpty else {
            throw AgentKickError.workingDirectoryNotSet(project.id)
        }

        // 作業ディレクトリの存在確認
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: workingDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AgentKickError.workingDirectoryNotFound(workingDirectory)
        }

        // キックメソッドの確認
        guard agent.kickMethod == .cli else {
            throw AgentKickError.kickMethodNotSupported(agent.kickMethod)
        }

        // シミュレートモード時は実際のプロセスを起動せずに成功を返す
        if shouldSimulate {
            return AgentKickResult(
                success: true,
                agentId: agent.id,
                agentName: agent.name,
                message: "UITest mode: Kick simulated successfully",
                processId: nil
            )
        }

        // プロンプトを構築
        let prompt = buildPrompt(task: task, agent: agent, project: project)

        // Claude Code CLIを起動
        do {
            let processId = try await launchClaudeCode(
                workingDirectory: workingDirectory,
                prompt: prompt,
                agent: agent,
                task: task
            )

            return AgentKickResult(
                success: true,
                agentId: agent.id,
                agentName: agent.name,
                message: "Claude Code started successfully",
                processId: processId
            )
        } catch {
            throw AgentKickError.executionFailed(error.localizedDescription)
        }
    }

    /// タスク実行用のプロンプトを構築
    private func buildPrompt(task: Task, agent: Agent, project: Project) -> String {
        var promptParts: [String] = []

        // タスク情報
        promptParts.append("# Task: \(task.title)")
        promptParts.append("")
        promptParts.append("Task ID: \(task.id.value)")
        promptParts.append("Project: \(project.name)")

        if !task.description.isEmpty {
            promptParts.append("")
            promptParts.append("## Description")
            promptParts.append(task.description)
        }

        // 作業ディレクトリ情報
        if let workingDir = project.workingDirectory {
            promptParts.append("")
            promptParts.append("## Working Directory")
            promptParts.append("Path: \(workingDir)")
            promptParts.append("IMPORTANT: Create any output files within this directory.")
        }

        // 完了指示
        promptParts.append("")
        promptParts.append("## Instructions")
        promptParts.append("1. Complete the task as described above")
        promptParts.append("2. When done, update the task status to 'done' using the agent-pm MCP server")
        promptParts.append("   - Use: update_task_status with task_id='\(task.id.value)' and status='done'")

        return promptParts.joined(separator: "\n")
    }

    /// Claude CLIのパスを取得
    private func findClaudeCLI() throws -> String {
        // 1. カスタムパスが設定されている場合はそれを使用
        if let customPath = ProcessInfo.processInfo.environment["CLAUDE_CLI_PATH"] {
            return customPath
        }

        // 2. 一般的なパスを順番に確認
        let possiblePaths = [
            "/opt/homebrew/bin/claude",  // Apple Silicon Mac (Homebrew)
            "/usr/local/bin/claude",      // Intel Mac (Homebrew)
            "/usr/bin/claude"             // システムインストール
        ]

        let fileManager = FileManager.default
        for path in possiblePaths {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 3. which コマンドで探す
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["claude"]

        let pipe = Pipe()
        whichProcess.standardOutput = pipe

        try whichProcess.run()
        whichProcess.waitUntilExit()

        if whichProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }

        throw AgentKickError.claudeCLINotFound
    }

    /// Claude Code CLIを起動
    private func launchClaudeCode(
        workingDirectory: String,
        prompt: String,
        agent: Agent,
        task: Task
    ) async throws -> Int {
        let process = Process()

        // カスタムコマンドが設定されている場合はそれを使用
        if let kickCommand = agent.kickCommand, !kickCommand.isEmpty {
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", kickCommand]
        } else {
            // Claude CLIのパスを取得
            let claudePath = try findClaudeCLI()

            // プロンプトを一時ファイルに書き出す（長いプロンプトをシェル経由で渡すため）
            let promptFile = "/tmp/uc001_prompt_\(task.id.value).txt"
            try prompt.write(toFile: promptFile, atomically: true, encoding: .utf8)

            // nohupでバックグラウンド実行するシェルコマンドを構築
            // アプリ終了後もプロセスが継続するようにする
            // 注: ログインシェルを使用してプロファイルを読み込み、PATHを設定する
            var shellCommand = "source ~/.zshrc 2>/dev/null; source ~/.bashrc 2>/dev/null; cd '\(workingDirectory)' && nohup '\(claudePath)'"

            // システムプロンプトが設定されている場合（シングルクォートをエスケープ）
            if let systemPrompt = agent.systemPrompt, !systemPrompt.isEmpty {
                let escapedPrompt = systemPrompt.replacingOccurrences(of: "'", with: "'\"'\"'")
                shellCommand += " --system-prompt '\(escapedPrompt)'"
            }

            shellCommand += " --dangerously-skip-permissions"
            shellCommand += " -p \"$(cat '\(promptFile)')\""
            shellCommand += " > /tmp/uc001_claude_output.log 2>&1 &"

            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", shellCommand]
        }

        // 環境変数を設定
        var environment = ProcessInfo.processInfo.environment
        environment["TASK_ID"] = task.id.value
        environment["TASK_TITLE"] = task.title
        process.environment = environment

        // 実行
        try process.run()
        process.waitUntilExit()

        // バックグラウンドプロセスのPIDを返す（nohupで起動したため実際のPIDは取得できない）
        return 1
    }
}
