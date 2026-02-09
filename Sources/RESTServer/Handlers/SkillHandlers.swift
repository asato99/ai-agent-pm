import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - Skill Handlers

    // 参照: docs/design/AGENT_SKILLS.md

    /// GET /api/skills - 利用可能なスキル一覧
    func listSkills(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard context.agentId != nil else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        let skills = try skillDefinitionRepository.findAll()
        let dtos = skills.map { SkillDTO(from: $0) }
        return jsonResponse(dtos)
    }

    /// GET /api/agents/:agentId/skills - エージェントに割り当てられたスキル一覧
    func getAgentSkills(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let currentAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let targetAgentIdStr = context.parameters.get("agentId") else {
            return errorResponse(status: .badRequest, message: "Agent ID is required")
        }
        let targetAgentId = AgentID(value: targetAgentIdStr)

        // 自分または部下のみアクセス可能
        let isDescendant = try agentRepository.findAllDescendants(currentAgentId).contains(where: { $0.id == targetAgentId })
        guard targetAgentId == currentAgentId || isDescendant else {
            return errorResponse(status: .forbidden, message: "Access denied")
        }

        let skills = try agentSkillAssignmentRepository.findByAgentId(targetAgentId)
        let response = AgentSkillsResponse(
            agentId: targetAgentId.value,
            skills: skills.map { SkillDTO(from: $0) }
        )
        return jsonResponse(response)
    }

    /// PUT /api/agents/:agentId/skills - エージェントにスキルを割り当て
    func assignAgentSkills(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let currentAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let targetAgentIdStr = context.parameters.get("agentId") else {
            return errorResponse(status: .badRequest, message: "Agent ID is required")
        }
        let targetAgentId = AgentID(value: targetAgentIdStr)

        // 自分または部下のみ更新可能
        let isDescendant = try agentRepository.findAllDescendants(currentAgentId).contains(where: { $0.id == targetAgentId })
        guard targetAgentId == currentAgentId || isDescendant else {
            return errorResponse(status: .forbidden, message: "Access denied")
        }

        // Parse request body
        let body = try await request.body.collect(upTo: 1024 * 1024)
        guard let data = body.getData(at: 0, length: body.readableBytes),
              let assignRequest = try? JSONDecoder().decode(AssignSkillsRequest.self, from: data) else {
            return errorResponse(status: .badRequest, message: "Invalid request body")
        }

        // スキルIDをドメイン型に変換
        let skillIds = assignRequest.skillIds.map { SkillID(value: $0) }

        // 全スキルIDが存在するか確認
        for skillId in skillIds {
            guard try skillDefinitionRepository.findById(skillId) != nil else {
                return errorResponse(status: .badRequest, message: "Skill not found: \(skillId.value)")
            }
        }

        // 割り当て実行
        try agentSkillAssignmentRepository.assignSkills(agentId: targetAgentId, skillIds: skillIds)

        // 更新後のスキル一覧を返す
        let skills = try agentSkillAssignmentRepository.findByAgentId(targetAgentId)
        let response = AgentSkillsResponse(
            agentId: targetAgentId.value,
            skills: skills.map { SkillDTO(from: $0) }
        )
        return jsonResponse(response)
    }

}
