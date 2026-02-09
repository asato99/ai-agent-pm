// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Help Tool

extension MCPServer {

    // MARK: - Help Tool
    // 参照: docs/design/TOOL_AUTHORIZATION_ENHANCEMENT.md

    /// helpツール実行: コンテキストに応じた利用可能ツール一覧/詳細を返す
    func executeHelp(caller: CallerType, toolName: String?) -> [String: Any] {
        // コンテキスト情報を構築
        var context: [String: Any] = [
            "caller_type": callerTypeDescription(caller)
        ]

        if let session = caller.session {
            context["session_purpose"] = session.purpose.rawValue
            context["agent_id"] = session.agentId.value
            context["project_id"] = session.projectId.value
        }

        // 利用可能なツールをフィルタリング
        let availableTools = filterAvailableTools(for: caller)

        if let toolName = toolName {
            // 特定ツールの詳細を返す
            return buildToolDetail(toolName: toolName, caller: caller, context: context)
        } else {
            // ツール一覧を返す
            return buildToolList(availableTools: availableTools, caller: caller, context: context)
        }
    }

    /// CallerTypeの説明文字列を返す
    func callerTypeDescription(_ caller: CallerType) -> String {
        switch caller {
        case .coordinator:
            return "coordinator"
        case .manager:
            return "manager"
        case .worker:
            return "worker"
        case .unauthenticated:
            return "unauthenticated"
        }
    }

    /// 呼び出し元が利用可能なツール名一覧を取得
    func filterAvailableTools(for caller: CallerType) -> [String] {
        ToolAuthorization.permissions.compactMap { (toolName, permission) -> String? in
            if canAccess(permission: permission, caller: caller) {
                return toolName
            }
            return nil
        }.sorted()
    }

    /// 権限チェック（簡易版: 実際の認可エラーをthrowせずにbool返却）
    func canAccess(permission: ToolPermission, caller: CallerType) -> Bool {
        switch (permission, caller) {
        case (.unauthenticated, _):
            return true

        case (.coordinatorOnly, .coordinator):
            return true
        case (.coordinatorOnly, _):
            return false

        case (.managerOnly, .manager):
            return true
        case (.managerOnly, _):
            return false

        case (.workerOnly, .worker):
            return true
        case (.workerOnly, _):
            return false

        case (.authenticated, .manager), (.authenticated, .worker):
            return true
        case (.authenticated, _):
            return false

        case (.chatOnly, .manager(_, let session)), (.chatOnly, .worker(_, let session)):
            return session.purpose == .chat
        case (.chatOnly, _):
            return false

        case (.taskOnly, .manager(_, let session)), (.taskOnly, .worker(_, let session)):
            return session.purpose == .task
        case (.taskOnly, _):
            return false
        }
    }

    /// ツール一覧を構築
    func buildToolList(availableTools: [String], caller: CallerType, context: [String: Any]) -> [String: Any] {
        let allToolDefs = ToolDefinitions.all()
        let toolDefsByName = Dictionary(uniqueKeysWithValues: allToolDefs.compactMap { def -> (String, [String: Any])? in
            guard let name = def["name"] as? String else { return nil }
            return (name, def)
        })

        var toolList: [[String: Any]] = []
        for toolName in availableTools {
            if let def = toolDefsByName[toolName] {
                let permission = ToolAuthorization.permissions[toolName] ?? .authenticated
                toolList.append([
                    "name": toolName,
                    "description": def["description"] as? String ?? "",
                    "category": permission.rawValue
                ])
            }
        }

        // 利用不可ツールの情報を追加
        var unavailableInfo: [String: String] = [:]

        // chatOnly ツールがtaskセッションで利用不可の場合
        if case .manager(_, let session) = caller, session.purpose == .task {
            unavailableInfo["chat_tools"] = "チャットツール（get_pending_messages, send_message）はpurpose=chatのセッションでのみ利用可能です"
        } else if case .worker(_, let session) = caller, session.purpose == .task {
            unavailableInfo["chat_tools"] = "チャットツール（get_pending_messages, send_message）はpurpose=chatのセッションでのみ利用可能です"
        }

        // 未認証の場合
        if case .unauthenticated = caller {
            unavailableInfo["authenticated_tools"] = "認証が必要です。authenticateツールを使用してください"
        }

        // Coordinator でない場合
        if case .coordinator = caller {
            // Coordinatorは全て利用可能
        } else if case .unauthenticated = caller {
            unavailableInfo["coordinator_tools"] = "Coordinator専用ツールは利用できません"
        } else {
            unavailableInfo["coordinator_tools"] = "Coordinator専用ツール（health_check等）は利用できません"
        }

        var result: [String: Any] = [
            "context": context,
            "available_tools": toolList,
            "total_available": toolList.count
        ]

        if !unavailableInfo.isEmpty {
            result["unavailable_info"] = unavailableInfo
        }

        return result
    }

    /// 特定ツールの詳細を構築
    func buildToolDetail(toolName: String, caller: CallerType, context: [String: Any]) -> [String: Any] {
        let allToolDefs = ToolDefinitions.all()
        guard let def = allToolDefs.first(where: { ($0["name"] as? String) == toolName }) else {
            return [
                "context": context,
                "error": "Tool '\(toolName)' not found"
            ]
        }

        let permission = ToolAuthorization.permissions[toolName] ?? .authenticated
        let isAvailable = canAccess(permission: permission, caller: caller)

        var result: [String: Any] = [
            "context": context,
            "name": toolName,
            "description": def["description"] as? String ?? "",
            "category": permission.rawValue,
            "available": isAvailable
        ]

        // パラメータ情報を抽出
        if let inputSchema = def["inputSchema"] as? [String: Any] {
            if let properties = inputSchema["properties"] as? [String: Any] {
                var parameters: [[String: Any]] = []
                let requiredParams = inputSchema["required"] as? [String] ?? []

                for (paramName, paramDef) in properties {
                    guard let paramDict = paramDef as? [String: Any] else { continue }
                    var paramInfo: [String: Any] = [
                        "name": paramName,
                        "type": paramDict["type"] as? String ?? "string",
                        "required": requiredParams.contains(paramName),
                        "description": paramDict["description"] as? String ?? ""
                    ]
                    if let enumValues = paramDict["enum"] as? [String] {
                        paramInfo["enum"] = enumValues
                    }
                    parameters.append(paramInfo)
                }
                result["parameters"] = parameters.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
            }
        }

        // 利用不可の理由を追加
        if !isAvailable {
            result["reason"] = unavailabilityReason(permission: permission, caller: caller)
        }

        return result
    }

    /// 利用不可の理由を返す
    func unavailabilityReason(permission: ToolPermission, caller: CallerType) -> String {
        switch permission {
        case .coordinatorOnly:
            return "このツールはCoordinator専用です"
        case .managerOnly:
            return "このツールはManager専用です"
        case .workerOnly:
            return "このツールはWorker専用です"
        case .authenticated:
            return "このツールは認証が必要です。authenticateツールを使用してください"
        case .chatOnly:
            if let session = caller.session {
                return "このツールはpurpose=chatのセッションでのみ利用可能です。現在のセッションはpurpose=\(session.purpose.rawValue)です"
            }
            return "このツールはチャットセッションでのみ利用可能です"
        case .taskOnly:
            if let session = caller.session {
                return "このツールはpurpose=taskのセッションでのみ利用可能です。現在のセッションはpurpose=\(session.purpose.rawValue)です"
            }
            return "このツールはタスクセッションでのみ利用可能です"
        case .unauthenticated:
            return "" // 未認証ツールは常に利用可能
        }
    }
}
