import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - Project Handlers


    func listProjects(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // Return only projects that the logged-in agent is assigned to
        // Reference: docs/requirements/PROJECTS.md - Agent Assignment
        let projects = try projectAgentAssignmentRepository.findProjectsByAgent(agentId)
        debugLog("listProjects: agentId=\(agentId.value), assigned projects count=\(projects.count)")
        for p in projects {
            debugLog("  - assigned project: \(p.id.value) (\(p.name))")
        }
        var summaries: [ProjectSummaryDTO] = []

        for project in projects {
            let tasks = try taskRepository.findByProject(project.id, status: nil)
            let counts = calculateTaskCounts(tasks: tasks, agentId: agentId)
            summaries.append(ProjectSummaryDTO(from: project, taskCounts: counts.counts, myTaskCount: counts.myTasks))
        }

        debugLog("listProjects: returning \(summaries.count) projects")
        return jsonResponse(summaries)
    }

    func getProject(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Missing project ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        guard let project = try projectRepository.findById(projectId) else {
            return errorResponse(status: .notFound, message: "Project not found")
        }

        let tasks = try taskRepository.findByProject(projectId, status: nil)
        let counts = calculateTaskCounts(tasks: tasks, agentId: agentId)

        // Phase 2.2: ログイン中エージェントのワーキングディレクトリを取得
        let workingDirectory = try workingDirectoryRepository.findByAgentAndProject(agentId: agentId, projectId: projectId)
        let summary = ProjectSummaryDTO(
            from: project,
            taskCounts: counts.counts,
            myTaskCount: counts.myTasks,
            myWorkingDirectory: workingDirectory?.workingDirectory
        )

        return jsonResponse(summary)
    }

    /// PUT /api/projects/:projectId/my-working-directory - ワーキングディレクトリを設定
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.2
    func setMyWorkingDirectory(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Missing project ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        guard try projectRepository.findById(projectId) != nil else {
            return errorResponse(status: .notFound, message: "Project not found")
        }

        // Parse request body
        let body = try await request.body.collect(upTo: 1024 * 1024)
        guard let data = body.getData(at: 0, length: body.readableBytes),
              let setRequest = try? JSONDecoder().decode(SetWorkingDirectoryRequest.self, from: data) else {
            return errorResponse(status: .badRequest, message: "Invalid request body")
        }

        // Validate working directory is not empty
        let workingDir = setRequest.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workingDir.isEmpty else {
            return errorResponse(status: .badRequest, message: "Working directory cannot be empty")
        }

        // Check if already exists and update, or create new
        if var existing = try workingDirectoryRepository.findByAgentAndProject(agentId: agentId, projectId: projectId) {
            existing.updateWorkingDirectory(workingDir)
            try workingDirectoryRepository.save(existing)
            return jsonResponse(WorkingDirectoryDTO(workingDirectory: existing.workingDirectory))
        } else {
            let newEntry = AgentWorkingDirectory.create(
                agentId: agentId,
                projectId: projectId,
                workingDirectory: workingDir
            )
            try workingDirectoryRepository.save(newEntry)
            var response = jsonResponse(WorkingDirectoryDTO(workingDirectory: newEntry.workingDirectory))
            response.status = .created
            return response
        }
    }

    /// DELETE /api/projects/:projectId/my-working-directory - ワーキングディレクトリ設定を削除
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.2
    func deleteMyWorkingDirectory(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Missing project ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        guard try projectRepository.findById(projectId) != nil else {
            return errorResponse(status: .notFound, message: "Project not found")
        }

        try workingDirectoryRepository.deleteByAgentAndProject(agentId: agentId, projectId: projectId)
        return Response(status: .noContent)
    }

}
