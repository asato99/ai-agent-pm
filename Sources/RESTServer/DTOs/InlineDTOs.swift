import Foundation
import Domain

// MARK: - Log Upload DTOs

/// ログアップロードレスポンス
/// 参照: docs/design/LOG_TRANSFER_DESIGN.md
struct LogUploadResponse: Encodable {
    let success: Bool
    let executionLogId: String
    let logFilePath: String
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case success
        case executionLogId = "execution_log_id"
        case logFilePath = "log_file_path"
        case fileSize = "file_size"
    }
}

// MARK: - Auth DTOs

struct LoginRequest: Decodable {
    let agentId: String
    let passkey: String
}

struct LoginResponse: Encodable {
    let sessionToken: String
    let agent: AgentDTO
    let expiresAt: String
}

// MARK: - Task Permissions DTO

struct TaskPermissionsDTO: Encodable {
    let canEdit: Bool
    let canChangeStatus: Bool
    let canReassign: Bool
    let validStatusTransitions: [String]
    let reason: String?
}

// MARK: - Handoff DTOs

struct HandoffDTO: Encodable {
    let id: String
    let taskId: String
    let fromAgentId: String
    let toAgentId: String?
    let summary: String
    let context: String?
    let recommendations: String?
    let acceptedAt: String?
    let createdAt: String
    let isPending: Bool
    let isTargeted: Bool

    init(from handoff: Handoff) {
        self.id = handoff.id.value
        self.taskId = handoff.taskId.value
        self.fromAgentId = handoff.fromAgentId.value
        self.toAgentId = handoff.toAgentId?.value
        self.summary = handoff.summary
        self.context = handoff.context
        self.recommendations = handoff.recommendations
        self.acceptedAt = handoff.acceptedAt.map { ISO8601DateFormatter().string(from: $0) }
        self.createdAt = ISO8601DateFormatter().string(from: handoff.createdAt)
        self.isPending = handoff.isPending
        self.isTargeted = handoff.isTargeted
    }
}

struct CreateHandoffRequest: Decodable {
    let taskId: String
    let toAgentId: String?
    let summary: String
    let context: String?
    let recommendations: String?
}

// MARK: - Working Directory DTOs
// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.2

struct SetWorkingDirectoryRequest: Decodable {
    let workingDirectory: String
}

struct WorkingDirectoryDTO: Encodable {
    let workingDirectory: String
}
