// Sources/RESTServer/DTOs/ProjectDTO.swift
// AI Agent PM - REST API Server

import Foundation
import Domain

/// Project data transfer object for REST API
public struct ProjectDTO: Codable {
    let id: String
    let name: String
    let description: String
    let status: String
    let createdAt: String
    let updatedAt: String

    init(from project: Project) {
        self.id = project.id.value
        self.name = project.name
        self.description = project.description ?? ""
        self.status = project.status.rawValue
        self.createdAt = ISO8601DateFormatter().string(from: project.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: project.updatedAt)
    }
}

/// Project summary with task counts for REST API
/// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.2
public struct ProjectSummaryDTO: Codable {
    let id: String
    let name: String
    let description: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let taskCount: Int
    let completedCount: Int
    let inProgressCount: Int
    let blockedCount: Int
    let myTaskCount: Int
    /// ログイン中エージェントのこのプロジェクトでのワーキングディレクトリ（設定されている場合）
    let myWorkingDirectory: String?

    init(from project: Project, taskCounts: TaskCounts, myTaskCount: Int, myWorkingDirectory: String? = nil) {
        self.id = project.id.value
        self.name = project.name
        self.description = project.description ?? ""
        self.status = project.status.rawValue
        self.createdAt = ISO8601DateFormatter().string(from: project.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: project.updatedAt)
        self.taskCount = taskCounts.total
        self.completedCount = taskCounts.done
        self.inProgressCount = taskCounts.inProgress
        self.blockedCount = taskCounts.blocked
        self.myTaskCount = myTaskCount
        self.myWorkingDirectory = myWorkingDirectory
    }
}

/// Task count breakdown
public struct TaskCounts {
    let total: Int
    let done: Int
    let inProgress: Int
    let blocked: Int

    static var zero: TaskCounts {
        TaskCounts(total: 0, done: 0, inProgress: 0, blocked: 0)
    }
}
