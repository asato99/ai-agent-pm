// Sources/MCPServer/App.swift
// AI Agent PM - MCP Server

import ArgumentParser
import Foundation
import Infrastructure
import Domain

// MARK: - Constants

enum AppConstants {
    static let appName = "AIAgentPM"
    static let defaultAgentId = "agt_claude"
    static let defaultAgentName = "Claude Code"
    static let defaultProjectId = "prj_default"
    static let defaultProjectName = "Default Project"

    /// ~/Library/Application Support/AIAgentPM/
    static var appSupportDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/\(appName)"
    }

    /// デフォルトDBパス
    static var defaultDatabasePath: String {
        "\(appSupportDirectory)/data.db"
    }

    /// Claude Code設定ファイルパス
    static var claudeConfigPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/claude_desktop_config.json"
    }
}

// MARK: - Main Command

@main
struct MCPServerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-server-pm",
        abstract: "AI Agent Project Manager - MCP Server",
        version: "0.1.0",
        subcommands: [Serve.self, Setup.self, Install.self, Status.self],
        defaultSubcommand: Serve.self
    )
}

// MARK: - Serve Command

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "MCPサーバーを起動（Claude Codeから自動呼び出し）"
    )

    @Option(name: .long, help: "データベースパス（省略時: デフォルト位置）")
    var db: String?

    @Option(name: .long, help: "エージェントID（省略時: agt_claude）")
    var agentId: String?

    @Option(name: .long, help: "プロジェクトID（省略時: prj_default）")
    var projectId: String?

    func run() throws {
        let dbPath = db ?? AppConstants.defaultDatabasePath
        let agent = agentId ?? AppConstants.defaultAgentId
        let project = projectId ?? AppConstants.defaultProjectId

        // 初回起動時は自動セットアップ
        if !FileManager.default.fileExists(atPath: dbPath) {
            try performAutoSetup(dbPath: dbPath)
        }

        let database = try DatabaseSetup.createDatabase(at: dbPath)
        let server = MCPServer(
            database: database,
            agentId: agent,
            projectId: project
        )
        try server.run()
    }

    private func performAutoSetup(dbPath: String) throws {
        // ディレクトリ作成
        let directory = (dbPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        let database = try DatabaseSetup.createDatabase(at: dbPath)
        let projectRepo = ProjectRepository(database: database)
        let agentRepo = AgentRepository(database: database)

        // デフォルトプロジェクト作成
        let projectId = ProjectID(value: AppConstants.defaultProjectId)
        let project = Project(id: projectId, name: AppConstants.defaultProjectName)
        try projectRepo.save(project)

        // デフォルトエージェント作成
        let agent = Agent(
            id: AgentID(value: AppConstants.defaultAgentId),
            projectId: projectId,
            name: AppConstants.defaultAgentName,
            role: "AI Assistant",
            type: .ai
        )
        try agentRepo.save(agent)

        FileHandle.standardError.write("[mcp-server-pm] Auto-setup completed\n".data(using: .utf8)!)
    }
}

// MARK: - Setup Command

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "初期セットアップを実行（DB作成、デフォルトデータ投入）"
    )

    @Flag(name: .long, help: "サンプルタスクも作成")
    var withSampleTasks = false

    func run() throws {
        let dbPath = AppConstants.defaultDatabasePath

        print("AI Agent PM セットアップ")
        print("========================")
        print("")

        // ディレクトリ作成
        let directory = (dbPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        print("✓ ディレクトリ作成: \(directory)")

        // DB作成
        let database = try DatabaseSetup.createDatabase(at: dbPath)
        print("✓ データベース作成: \(dbPath)")

        let projectRepo = ProjectRepository(database: database)
        let agentRepo = AgentRepository(database: database)
        let taskRepo = TaskRepository(database: database)

        // プロジェクト作成
        let projectId = ProjectID(value: AppConstants.defaultProjectId)
        let project = Project(id: projectId, name: AppConstants.defaultProjectName)
        try projectRepo.save(project)
        print("✓ プロジェクト作成: \(project.name)")

        // エージェント作成
        let agent = Agent(
            id: AgentID(value: AppConstants.defaultAgentId),
            projectId: projectId,
            name: AppConstants.defaultAgentName,
            role: "AI Assistant",
            type: .ai
        )
        try agentRepo.save(agent)
        print("✓ エージェント作成: \(agent.name) (\(agent.id.value))")

        // サンプルタスク
        if withSampleTasks {
            let tasks = [
                Task(id: TaskID.generate(), projectId: projectId, title: "サンプルタスク1", status: .todo),
                Task(id: TaskID.generate(), projectId: projectId, title: "サンプルタスク2", status: .backlog),
                Task(id: TaskID.generate(), projectId: projectId, title: "サンプルタスク3", status: .backlog),
            ]
            for task in tasks {
                try taskRepo.save(task)
                print("✓ タスク作成: \(task.title)")
            }
        }

        print("")
        print("セットアップ完了!")
        print("")
        print("次のステップ:")
        print("  mcp-server-pm install  # Claude Code設定を自動生成")
    }
}

// MARK: - Install Command

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Claude Code CLIにMCPサーバーを登録"
    )

    @Flag(name: .long, help: "既存の設定を上書き")
    var force = false

    func run() throws {
        print("Claude Code MCP サーバー登録")
        print("============================")
        print("")

        // 実行ファイルのパスを取得
        let executablePath = CommandLine.arguments[0]
        let absolutePath: String

        if executablePath.hasPrefix("/") {
            absolutePath = executablePath
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            absolutePath = (currentDir as NSString).appendingPathComponent(executablePath)
        }

        // claude コマンドが利用可能か確認
        let claudeAvailable = isCommandAvailable("claude")

        if claudeAvailable {
            try installViaCLI(serverPath: absolutePath)
        } else {
            print("⚠ claude コマンドが見つかりません")
            print("  Claude Code CLIをインストールしてください:")
            print("  https://claude.ai/code")
            print("")
            print("手動でMCPサーバーを追加するには:")
            print("  claude mcp add -s user agent-pm \(absolutePath)")
        }
    }

    /// claude mcp add コマンドで登録
    private func installViaCLI(serverPath: String) throws {
        // 既存の登録を確認
        let checkProcess = Process()
        checkProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        checkProcess.arguments = ["claude", "mcp", "get", "agent-pm"]

        let checkPipe = Pipe()
        checkProcess.standardOutput = checkPipe
        checkProcess.standardError = checkPipe

        try checkProcess.run()
        checkProcess.waitUntilExit()

        let alreadyExists = checkProcess.terminationStatus == 0

        if alreadyExists && !force {
            print("✓ agent-pm は既に登録されています")
            print("")
            print("上書きするには --force オプションを使用してください")
            return
        }

        // 既存の登録を削除（--forceの場合）
        if alreadyExists && force {
            let removeProcess = Process()
            removeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            removeProcess.arguments = ["claude", "mcp", "remove", "agent-pm", "-s", "user"]
            removeProcess.standardOutput = FileHandle.nullDevice
            removeProcess.standardError = FileHandle.nullDevice

            try removeProcess.run()
            removeProcess.waitUntilExit()
            print("✓ 既存の設定を削除しました")
        }

        // 新規登録
        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        addProcess.arguments = ["claude", "mcp", "add", "-s", "user", "-t", "stdio", "agent-pm", serverPath]

        let addPipe = Pipe()
        addProcess.standardOutput = addPipe
        addProcess.standardError = addPipe

        try addProcess.run()
        addProcess.waitUntilExit()

        if addProcess.terminationStatus == 0 {
            print("✓ MCPサーバーを登録しました")
            print("")
            print("登録完了!")
            print("")
            print("動作確認:")
            print("  1. Claude Codeを再起動")
            print("  2. 「get_my_profileを呼び出して」と入力")
        } else {
            let outputData = addPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            print("✗ 登録に失敗しました")
            print(output)
        }
    }

    /// コマンドが利用可能か確認
    private func isCommandAvailable(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Status Command

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "現在の状態を表示"
    )

    func run() throws {
        print("AI Agent PM ステータス")
        print("======================")
        print("")

        // DB確認
        let dbPath = AppConstants.defaultDatabasePath
        if FileManager.default.fileExists(atPath: dbPath) {
            print("✓ データベース: \(dbPath)")

            let database = try DatabaseSetup.createDatabase(at: dbPath)
            let projectRepo = ProjectRepository(database: database)
            let agentRepo = AgentRepository(database: database)
            let taskRepo = TaskRepository(database: database)

            let projects = try projectRepo.findAll()
            print("  プロジェクト数: \(projects.count)")

            for project in projects {
                let agents = try agentRepo.findAll(projectId: project.id)
                let tasks = try taskRepo.findAll(projectId: project.id)
                print("  - \(project.name): エージェント \(agents.count)件, タスク \(tasks.count)件")
            }
        } else {
            print("✗ データベース: 未作成")
            print("  → mcp-server-pm setup を実行してください")
        }

        print("")

        // Claude Code設定確認
        let configPath = AppConstants.claudeConfigPath
        if FileManager.default.fileExists(atPath: configPath) {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            if let config = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let mcpServers = config["mcpServers"] as? [String: Any],
               mcpServers["agent-pm"] != nil {
                print("✓ Claude Code設定: インストール済み")
            } else {
                print("✗ Claude Code設定: agent-pm 未設定")
                print("  → mcp-server-pm install を実行してください")
            }
        } else {
            print("✗ Claude Code設定: ファイルなし")
            print("  → mcp-server-pm install を実行してください")
        }
    }
}
