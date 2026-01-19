// Sources/RESTServer/DTOs/TaskDTO.swift
// AI Agent PM - REST API Server

import Foundation
import Domain

/// Task data transfer object for REST API
public struct TaskDTO: Codable {
    let id: String
    let projectId: String
    let title: String
    let description: String
    let status: String
    let priority: String
    let assigneeId: String?
    let dependencies: [String]
    let parentTaskId: String?
    let createdAt: String
    let updatedAt: String

    init(from task: Task) {
        self.id = task.id.value
        self.projectId = task.projectId.value
        self.title = task.title
        self.description = task.description
        self.status = task.status.rawValue
        self.priority = task.priority.rawValue
        self.assigneeId = task.assigneeId?.value
        self.dependencies = task.dependencies.map { $0.value }
        self.parentTaskId = task.parentTaskId?.value
        self.createdAt = ISO8601DateFormatter().string(from: task.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: task.updatedAt)
    }
}

/// Request body for creating a task
public struct CreateTaskRequest: Decodable {
    public let title: String
    public let description: String?
    public let priority: String?
    public let assigneeId: String?
    public let dependencies: [String]?
}

/// Request body for updating a task
public struct UpdateTaskRequest: Decodable {
    public let title: String?
    public let description: String?
    public let status: String?
    public let priority: String?
    public let assigneeId: String?
    public let dependencies: [String]?
}
