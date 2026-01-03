// Sources/UseCase/WorkflowTemplateUseCases.swift
// ワークフローテンプレート関連のユースケース
// 参照: docs/requirements/WORKFLOW_TEMPLATES.md

import Foundation
import Domain

// MARK: - CreateTemplateUseCase

/// テンプレート作成ユースケース (UC-WT-01)
public struct CreateTemplateUseCase: Sendable {
    private let templateRepository: any WorkflowTemplateRepositoryProtocol
    private let templateTaskRepository: any TemplateTaskRepositoryProtocol

    public init(
        templateRepository: any WorkflowTemplateRepositoryProtocol,
        templateTaskRepository: any TemplateTaskRepositoryProtocol
    ) {
        self.templateRepository = templateRepository
        self.templateTaskRepository = templateTaskRepository
    }

    public struct Input {
        public let name: String
        public let description: String
        public let variables: [String]
        public let tasks: [TaskInput]

        public struct TaskInput {
            public let title: String
            public let description: String
            public let order: Int
            public let dependsOnOrders: [Int]
            public let defaultAssigneeRole: AgentRoleType?
            public let defaultPriority: TaskPriority
            public let estimatedMinutes: Int?

            public init(
                title: String,
                description: String = "",
                order: Int,
                dependsOnOrders: [Int] = [],
                defaultAssigneeRole: AgentRoleType? = nil,
                defaultPriority: TaskPriority = .medium,
                estimatedMinutes: Int? = nil
            ) {
                self.title = title
                self.description = description
                self.order = order
                self.dependsOnOrders = dependsOnOrders
                self.defaultAssigneeRole = defaultAssigneeRole
                self.defaultPriority = defaultPriority
                self.estimatedMinutes = estimatedMinutes
            }
        }

        public init(
            name: String,
            description: String = "",
            variables: [String] = [],
            tasks: [TaskInput] = []
        ) {
            self.name = name
            self.description = description
            self.variables = variables
            self.tasks = tasks
        }
    }

    public func execute(input: Input) throws -> WorkflowTemplate {
        // バリデーション
        let trimmedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw UseCaseError.validationFailed("Template name cannot be empty")
        }
        guard trimmedName.count <= 100 else {
            throw UseCaseError.validationFailed("Template name must be 100 characters or less")
        }

        // 変数名の検証
        for variable in input.variables {
            guard WorkflowTemplate.isValidVariableName(variable) else {
                throw UseCaseError.validationFailed("Invalid variable name: \(variable)")
            }
        }

        // テンプレート作成
        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            name: trimmedName,
            description: input.description,
            variables: input.variables
        )
        try templateRepository.save(template)

        // タスク作成
        for taskInput in input.tasks {
            let task = TemplateTask(
                id: TemplateTaskID.generate(),
                templateId: template.id,
                title: taskInput.title,
                description: taskInput.description,
                order: taskInput.order,
                dependsOnOrders: taskInput.dependsOnOrders,
                defaultAssigneeRole: taskInput.defaultAssigneeRole,
                defaultPriority: taskInput.defaultPriority,
                estimatedMinutes: taskInput.estimatedMinutes
            )
            try templateTaskRepository.save(task)
        }

        return template
    }
}

// MARK: - InstantiateTemplateUseCase

/// テンプレートインスタンス化ユースケース (UC-WT-02)
public struct InstantiateTemplateUseCase: Sendable {
    private let templateRepository: any WorkflowTemplateRepositoryProtocol
    private let templateTaskRepository: any TemplateTaskRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol
    private let projectRepository: any ProjectRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        templateRepository: any WorkflowTemplateRepositoryProtocol,
        templateTaskRepository: any TemplateTaskRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol,
        projectRepository: any ProjectRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.templateRepository = templateRepository
        self.templateTaskRepository = templateTaskRepository
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository
        self.eventRepository = eventRepository
    }

    public struct Input {
        public let templateId: WorkflowTemplateID
        public let projectId: ProjectID
        public let variableValues: [String: String]
        public let assigneeId: AgentID?

        public init(
            templateId: WorkflowTemplateID,
            projectId: ProjectID,
            variableValues: [String: String] = [:],
            assigneeId: AgentID? = nil
        ) {
            self.templateId = templateId
            self.projectId = projectId
            self.variableValues = variableValues
            self.assigneeId = assigneeId
        }
    }

    public func execute(input: Input) throws -> InstantiationResult {
        // テンプレートの存在確認
        guard let template = try templateRepository.findById(input.templateId) else {
            throw UseCaseError.templateNotFound(input.templateId)
        }

        // アクティブでないテンプレートはインスタンス化不可
        guard template.isActive else {
            throw UseCaseError.validationFailed("Cannot instantiate archived template")
        }

        // プロジェクトの存在確認
        guard try projectRepository.findById(input.projectId) != nil else {
            throw UseCaseError.projectNotFound(input.projectId)
        }

        // テンプレートタスクを取得（order順）
        let templateTasks = try templateTaskRepository.findByTemplate(input.templateId)

        // タスクを生成
        var createdTasks: [Task] = []
        var orderToTaskIdMap: [Int: TaskID] = [:]

        for templateTask in templateTasks {
            let taskId = TaskID.generate()
            orderToTaskIdMap[templateTask.order] = taskId

            // 依存関係をTaskIDに変換
            let dependencies = templateTask.dependsOnOrders.compactMap { orderToTaskIdMap[$0] }

            let task = Task(
                id: taskId,
                projectId: input.projectId,
                title: templateTask.resolveTitle(with: input.variableValues),
                description: templateTask.resolveDescription(with: input.variableValues),
                status: .backlog,
                priority: templateTask.defaultPriority,
                assigneeId: input.assigneeId,
                dependencies: dependencies,
                estimatedMinutes: templateTask.estimatedMinutes
            )
            try taskRepository.save(task)
            createdTasks.append(task)

            // イベント記録
            let event = StateChangeEvent(
                id: EventID.generate(),
                projectId: input.projectId,
                entityType: .task,
                entityId: task.id.value,
                eventType: .created,
                newState: task.status.rawValue,
                metadata: ["templateId": input.templateId.value]
            )
            try eventRepository.save(event)
        }

        return InstantiationResult(
            templateId: input.templateId,
            projectId: input.projectId,
            createdTasks: createdTasks
        )
    }
}

// MARK: - UpdateTemplateUseCase

/// テンプレート更新ユースケース (UC-WT-03)
public struct UpdateTemplateUseCase: Sendable {
    private let templateRepository: any WorkflowTemplateRepositoryProtocol

    public init(templateRepository: any WorkflowTemplateRepositoryProtocol) {
        self.templateRepository = templateRepository
    }

    public func execute(
        templateId: WorkflowTemplateID,
        name: String? = nil,
        description: String? = nil,
        variables: [String]? = nil
    ) throws -> WorkflowTemplate {
        guard var template = try templateRepository.findById(templateId) else {
            throw UseCaseError.templateNotFound(templateId)
        }

        if let name = name {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw UseCaseError.validationFailed("Template name cannot be empty")
            }
            guard trimmedName.count <= 100 else {
                throw UseCaseError.validationFailed("Template name must be 100 characters or less")
            }
            template.name = trimmedName
        }

        if let description = description {
            template.description = description
        }

        if let variables = variables {
            for variable in variables {
                guard WorkflowTemplate.isValidVariableName(variable) else {
                    throw UseCaseError.validationFailed("Invalid variable name: \(variable)")
                }
            }
            template.variables = variables
        }

        template.updatedAt = Date()
        try templateRepository.save(template)

        return template
    }
}

// MARK: - ArchiveTemplateUseCase

/// テンプレートアーカイブユースケース (UC-WT-04)
public struct ArchiveTemplateUseCase: Sendable {
    private let templateRepository: any WorkflowTemplateRepositoryProtocol

    public init(templateRepository: any WorkflowTemplateRepositoryProtocol) {
        self.templateRepository = templateRepository
    }

    public func execute(templateId: WorkflowTemplateID) throws -> WorkflowTemplate {
        guard var template = try templateRepository.findById(templateId) else {
            throw UseCaseError.templateNotFound(templateId)
        }

        template.status = .archived
        template.updatedAt = Date()
        try templateRepository.save(template)

        return template
    }
}

// MARK: - ListTemplatesUseCase

/// テンプレート一覧取得ユースケース
public struct ListTemplatesUseCase: Sendable {
    private let templateRepository: any WorkflowTemplateRepositoryProtocol

    public init(templateRepository: any WorkflowTemplateRepositoryProtocol) {
        self.templateRepository = templateRepository
    }

    public func execute(includeArchived: Bool = false) throws -> [WorkflowTemplate] {
        try templateRepository.findAll(includeArchived: includeArchived)
    }
}

// MARK: - GetTemplateWithTasksUseCase

/// テンプレートとタスク取得ユースケース
public struct GetTemplateWithTasksUseCase: Sendable {
    private let templateRepository: any WorkflowTemplateRepositoryProtocol
    private let templateTaskRepository: any TemplateTaskRepositoryProtocol

    public init(
        templateRepository: any WorkflowTemplateRepositoryProtocol,
        templateTaskRepository: any TemplateTaskRepositoryProtocol
    ) {
        self.templateRepository = templateRepository
        self.templateTaskRepository = templateTaskRepository
    }

    public struct Result {
        public let template: WorkflowTemplate
        public let tasks: [TemplateTask]
    }

    public func execute(templateId: WorkflowTemplateID) throws -> Result? {
        guard let template = try templateRepository.findById(templateId) else {
            return nil
        }

        let tasks = try templateTaskRepository.findByTemplate(templateId)
        return Result(template: template, tasks: tasks)
    }
}
