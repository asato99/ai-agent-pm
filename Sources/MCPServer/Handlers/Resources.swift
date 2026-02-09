// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Resources

extension MCPServer {

    // MARK: - Resources List

    /// ステートレス設計: リソースURIにはIDを動的に指定
    /// 例: project://{project_id}/overview, agent://{agent_id}/profile
    func handleResourcesList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let resources: [[String: Any]] = [
            [
                "uri": "project://{project_id}/overview",
                "name": "Project Overview",
                "description": "指定プロジェクトの概要情報。{project_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ],
            [
                "uri": "project://{project_id}/tasks",
                "name": "Project Tasks",
                "description": "指定プロジェクト内の全タスク一覧。{project_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ],
            [
                "uri": "project://{project_id}/agents",
                "name": "Project Agents",
                "description": "全エージェント一覧",
                "mimeType": "application/json"
            ],
            [
                "uri": "agent://{agent_id}/profile",
                "name": "Agent Profile",
                "description": "指定エージェントのプロファイル。{agent_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ],
            [
                "uri": "agent://{agent_id}/tasks",
                "name": "Agent Tasks",
                "description": "指定エージェントに割り当てられたタスク。{agent_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ],
            [
                "uri": "task://{task_id}/detail",
                "name": "Task Detail",
                "description": "指定タスクの詳細情報。{task_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ],
            [
                "uri": "task://{task_id}/context",
                "name": "Task Context",
                "description": "指定タスクのコンテキスト情報。{task_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ]
        ]

        return JSONRPCResponse(id: request.id, result: ["resources": resources])
    }

    // MARK: - Resources Read

    func handleResourcesRead(_ request: JSONRPCRequest) -> JSONRPCResponse {
        guard let params = request.params,
              let uri = params["uri"]?.stringValue else {
            return JSONRPCResponse(id: request.id, error: JSONRPCError.invalidParams)
        }

        do {
            let content = try readResource(uri: uri)
            return JSONRPCResponse(id: request.id, result: [
                "contents": [
                    [
                        "uri": uri,
                        "mimeType": "application/json",
                        "text": formatResult(content)
                    ]
                ]
            ])
        } catch {
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32000, message: error.localizedDescription))
        }
    }

    func readResource(uri: String) throws -> Any {
        // Parse URI
        if uri.hasPrefix("project://") {
            return try readProjectResource(uri: uri)
        } else if uri.hasPrefix("agent://") {
            return try readAgentResource(uri: uri)
        } else if uri.hasPrefix("task://") {
            return try readTaskResource(uri: uri)
        } else {
            throw MCPError.invalidResourceURI(uri)
        }
    }

    func readProjectResource(uri: String) throws -> Any {
        let path = uri.replacingOccurrences(of: "project://", with: "")
        let components = path.split(separator: "/")

        guard components.count >= 2 else {
            throw MCPError.invalidResourceURI(uri)
        }

        let projectIdStr = String(components[0])
        let resource = String(components[1])

        switch resource {
        case "overview":
            guard let project = try projectRepository.findById(ProjectID(value: projectIdStr)) else {
                throw MCPError.projectNotFound(projectIdStr)
            }
            let tasks = try taskRepository.findAll(projectId: project.id)
            let agents = try agentRepository.findAll()

            let projectDict: [String: Any] = [
                "id": project.id.value,
                "name": project.name,
                "description": project.description,
                "status": project.status.rawValue
            ]

            let summaryDict: [String: Any] = [
                "total_tasks": tasks.count,
                "completed_tasks": tasks.filter { $0.status == .done }.count,
                "in_progress_tasks": tasks.filter { $0.status == .inProgress }.count,
                "blocked_tasks": tasks.filter { $0.status == .blocked }.count,
                "total_agents": agents.count,
                "ai_agents": agents.filter { $0.type == .ai }.count,
                "human_agents": agents.filter { $0.type == .human }.count
            ]

            return ["project": projectDict, "summary": summaryDict]
        case "tasks":
            let tasks = try taskRepository.findAll(projectId: ProjectID(value: projectIdStr))
            return tasks.map { taskToDict($0) }
        case "agents":
            let agents = try agentRepository.findAll()
            return agents.map { agentToDict($0) }
        default:
            throw MCPError.invalidResourceURI(uri)
        }
    }

    func readAgentResource(uri: String) throws -> Any {
        let path = uri.replacingOccurrences(of: "agent://", with: "")
        let components = path.split(separator: "/")

        guard components.count >= 2 else {
            throw MCPError.invalidResourceURI(uri)
        }

        let agentIdStr = String(components[0])
        let resource = String(components[1])
        let targetAgentId = AgentID(value: agentIdStr)

        switch resource {
        case "profile":
            guard let agent = try agentRepository.findById(targetAgentId) else {
                throw MCPError.agentNotFound(agentIdStr)
            }
            return agentToDict(agent)
        case "tasks":
            let tasks = try taskRepository.findByAssignee(targetAgentId)
            return tasks.map { taskToDict($0) }
        case "sessions":
            let sessions = try sessionRepository.findByAgent(targetAgentId)
            return sessions.map { sessionToDict($0) }
        default:
            throw MCPError.invalidResourceURI(uri)
        }
    }

    func readTaskResource(uri: String) throws -> Any {
        let path = uri.replacingOccurrences(of: "task://", with: "")
        let components = path.split(separator: "/")

        guard components.count >= 2 else {
            throw MCPError.invalidResourceURI(uri)
        }

        let taskIdStr = String(components[0])
        let resource = String(components[1])
        let taskId = TaskID(value: taskIdStr)

        guard let task = try taskRepository.findById(taskId) else {
            throw MCPError.taskNotFound(taskIdStr)
        }

        switch resource {
        case "detail":
            let latestContext = try contextRepository.findLatest(taskId: taskId)
            var result = taskToDict(task)
            if let ctx = latestContext {
                result["latest_context"] = contextToDict(ctx)
            }
            return result
        case "history":
            let events = try eventRepository.findByEntity(type: .task, id: taskIdStr)
            return events.map { eventToDict($0) }
        case "context":
            let contexts = try contextRepository.findByTask(taskId)
            return contexts.map { contextToDict($0) }
        default:
            throw MCPError.invalidResourceURI(uri)
        }
    }


}
