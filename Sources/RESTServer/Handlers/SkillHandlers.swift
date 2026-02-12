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

    /// POST /api/skills - スキル登録（multipart/form-data ZIPアップロード）
    /// MCPServer.registerSkill() に委譲し、ロジック重複を排除
    func registerSkill(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard context.agentId != nil else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        let contentType = request.headers[.contentType] ?? ""

        guard contentType.contains("multipart/form-data") else {
            return errorResponse(status: .unsupportedMediaType, message: "Content-Type must be multipart/form-data with a zip_file field")
        }

        guard let boundaryRange = contentType.range(of: "boundary="),
              let boundary = contentType[boundaryRange.upperBound...].split(separator: ";").first else {
            return errorResponse(status: .badRequest, message: "Missing boundary in Content-Type")
        }

        let body = try await request.body.collect(upTo: 2 * 1024 * 1024)
        guard let data = body.getData(at: 0, length: body.readableBytes) else {
            return errorResponse(status: .badRequest, message: "Empty request body")
        }

        let formData = parseMultipartFormData(data: data, boundary: String(boundary))

        guard let zipData = formData.files["zip_file"] else {
            return errorResponse(status: .badRequest, message: "zip_file field is required")
        }

        // ZIP データを一時ファイルに書き出し（mcpServer は file path を受け取る）
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).zip")
        try zipData.write(to: tempFile)

        // 一時ファイルのクリーンアップを保証
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let name = formData.fields["name"]
        let skillDescription = formData.fields["description"]
        let directoryName = formData.fields["directory_name"]

        // MCPServer に委譲
        do {
            let result = try mcpServer.registerSkill(
                zipFilePath: tempFile.path,
                folderPath: nil,
                skillMdContent: nil,
                name: name,
                description: skillDescription,
                directoryName: directoryName
            )

            // DB からスキル全体を取得して DTO に変換
            guard let skillId = result["skill_id"] as? String,
                  let skill = try skillDefinitionRepository.findById(SkillID(value: skillId)) else {
                return errorResponse(status: .internalServerError, message: "Failed to retrieve registered skill")
            }

            let response = RegisterSkillResponse(
                status: "created",
                skill: SkillDTO(from: skill)
            )
            let responseData = try JSONEncoder().encode(response)
            return Response(
                status: .created,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: responseData))
            )
        } catch let error as SkillError {
            switch error {
            case .directoryNameAlreadyExists(let n, _):
                return errorResponse(status: .conflict, message: "Directory name already exists: \(n)")
            case .emptyName:
                return errorResponse(status: .badRequest, message: "Skill name is required")
            case .invalidDirectoryName(let n):
                return errorResponse(status: .badRequest, message: "Invalid directory name: \(n)")
            case .descriptionTooLong(let count):
                return errorResponse(status: .badRequest, message: "Description too long: \(count) chars")
            case .archiveTooLarge(let bytes):
                return errorResponse(status: .badRequest, message: "Archive too large: \(bytes) bytes")
            default:
                return errorResponse(status: .badRequest, message: error.localizedDescription)
            }
        } catch let error as SkillArchiveError {
            return errorResponse(status: .badRequest, message: "Failed to process skill archive: \(error)")
        } catch let error as MCPError {
            return errorResponse(status: .badRequest, message: "\(error)")
        } catch {
            return errorResponse(status: .internalServerError, message: "Failed to create skill: \(error.localizedDescription)")
        }
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
