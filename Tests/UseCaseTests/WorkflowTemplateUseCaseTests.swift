// Tests/UseCaseTests/WorkflowTemplateUseCaseTests.swift
// Workflow template UseCase tests extracted from UseCaseTests.swift
// 参照: WORKFLOW_TEMPLATES.md

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Workflow Template UseCase Tests

final class WorkflowTemplateUseCaseTests: XCTestCase {

    var projectRepo: MockProjectRepository!
    var taskRepo: MockTaskRepository!
    var eventRepo: MockEventRepository!
    var templateRepo: MockWorkflowTemplateRepository!
    var templateTaskRepo: MockTemplateTaskRepository!

    override func setUp() {
        projectRepo = MockProjectRepository()
        taskRepo = MockTaskRepository()
        eventRepo = MockEventRepository()
        templateRepo = MockWorkflowTemplateRepository()
        templateTaskRepo = MockTemplateTaskRepository()
    }

    // MARK: - Create Template Tests

    func testCreateTemplateUseCase() throws {
        // テンプレート作成ユースケース
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        projectRepo.projects[project.id] = project

        let useCase = CreateTemplateUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo,
            projectRepository: projectRepo
        )

        let input = CreateTemplateUseCase.Input(
            projectId: project.id,
            name: "Feature Development",
            description: "機能開発のワークフロー",
            variables: ["feature_name", "module"],
            tasks: [
                CreateTemplateUseCase.Input.TaskInput(
                    title: "{{feature_name}} - 要件確認",
                    order: 1,
                    defaultPriority: .high
                ),
                CreateTemplateUseCase.Input.TaskInput(
                    title: "{{feature_name}} - 実装",
                    order: 2,
                    dependsOnOrders: [1]
                )
            ]
        )

        let template = try useCase.execute(input: input)

        XCTAssertEqual(template.name, "Feature Development")
        XCTAssertEqual(template.variables, ["feature_name", "module"])

        let tasks = try templateTaskRepo.findByTemplate(template.id)
        XCTAssertEqual(tasks.count, 2)
    }

    func testCreateTemplateUseCaseValidatesEmptyName() throws {
        // 空の名前でエラー
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        projectRepo.projects[project.id] = project

        let useCase = CreateTemplateUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo,
            projectRepository: projectRepo
        )

        let input = CreateTemplateUseCase.Input(projectId: project.id, name: "   ")

        XCTAssertThrowsError(try useCase.execute(input: input)) { error in
            XCTAssertTrue(error is UseCaseError)
        }
    }

    func testCreateTemplateUseCaseValidatesInvalidVariableName() throws {
        // 無効な変数名でエラー
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        projectRepo.projects[project.id] = project

        let useCase = CreateTemplateUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo,
            projectRepository: projectRepo
        )

        let input = CreateTemplateUseCase.Input(
            projectId: project.id,
            name: "Test",
            variables: ["123invalid"]
        )

        XCTAssertThrowsError(try useCase.execute(input: input)) { error in
            XCTAssertTrue(error is UseCaseError)
        }
    }

    // MARK: - Instantiate Template Tests

    func testInstantiateTemplateUseCase() throws {
        // インスタンス化ユースケース
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        projectRepo.projects[project.id] = project

        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: project.id,
            name: "Feature Development",
            variables: ["feature_name"]
        )
        templateRepo.templates[template.id] = template

        let task1 = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: template.id,
            title: "{{feature_name}} - 要件確認",
            order: 1
        )
        let task2 = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: template.id,
            title: "{{feature_name}} - 実装",
            order: 2,
            dependsOnOrders: [1]
        )
        templateTaskRepo.tasks[task1.id] = task1
        templateTaskRepo.tasks[task2.id] = task2

        let useCase = InstantiateTemplateUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo,
            taskRepository: taskRepo,
            projectRepository: projectRepo,
            eventRepository: eventRepo
        )

        let input = InstantiateTemplateUseCase.Input(
            templateId: template.id,
            projectId: project.id,
            variableValues: ["feature_name": "ログイン機能"]
        )

        let result = try useCase.execute(input: input)

        XCTAssertEqual(result.taskCount, 2)
        XCTAssertEqual(result.createdTasks[0].title, "ログイン機能 - 要件確認")
        XCTAssertEqual(result.createdTasks[1].title, "ログイン機能 - 実装")

        // 依存関係が正しく設定されていること
        XCTAssertTrue(result.createdTasks[1].dependencies.contains(result.createdTasks[0].id))
    }

    func testInstantiateTemplateUseCaseRejectsArchivedTemplate() throws {
        // アーカイブ済みテンプレートはインスタンス化不可
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        projectRepo.projects[project.id] = project

        var template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: project.id,
            name: "Archived Template"
        )
        template.status = .archived
        templateRepo.templates[template.id] = template

        let useCase = InstantiateTemplateUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo,
            taskRepository: taskRepo,
            projectRepository: projectRepo,
            eventRepository: eventRepo
        )

        let input = InstantiateTemplateUseCase.Input(
            templateId: template.id,
            projectId: project.id
        )

        XCTAssertThrowsError(try useCase.execute(input: input))
    }

    // MARK: - Update Template Tests

    func testUpdateTemplateUseCase() throws {
        // テンプレート更新ユースケース
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: projectId,
            name: "Original"
        )
        templateRepo.templates[template.id] = template

        let useCase = UpdateTemplateUseCase(templateRepository: templateRepo)

        let updated = try useCase.execute(
            templateId: template.id,
            name: "Updated",
            description: "New description"
        )

        XCTAssertEqual(updated.name, "Updated")
        XCTAssertEqual(updated.description, "New description")
    }

    // MARK: - Archive Template Tests

    func testArchiveTemplateUseCase() throws {
        // テンプレートアーカイブユースケース
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: projectId,
            name: "To Archive"
        )
        templateRepo.templates[template.id] = template

        let useCase = ArchiveTemplateUseCase(templateRepository: templateRepo)

        let archived = try useCase.execute(templateId: template.id)

        XCTAssertEqual(archived.status, .archived)
    }

    // MARK: - List Templates Tests

    func testListTemplatesUseCase() throws {
        // テンプレート一覧取得ユースケース
        let projectId = ProjectID.generate()
        let template1 = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Template1")
        var template2 = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Template2")
        template2.status = .archived

        templateRepo.templates[template1.id] = template1
        templateRepo.templates[template2.id] = template2

        let useCase = ListTemplatesUseCase(templateRepository: templateRepo)

        let activeOnly = try useCase.execute(projectId: projectId, includeArchived: false)
        XCTAssertEqual(activeOnly.count, 1)

        let all = try useCase.execute(projectId: projectId, includeArchived: true)
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Get Template With Tasks Tests

    func testGetTemplateWithTasksUseCase() throws {
        // テンプレートとタスク取得ユースケース
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: projectId,
            name: "Feature Development"
        )
        templateRepo.templates[template.id] = template

        let task1 = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: template.id,
            title: "Task 1",
            order: 1
        )
        let task2 = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: template.id,
            title: "Task 2",
            order: 2
        )
        templateTaskRepo.tasks[task1.id] = task1
        templateTaskRepo.tasks[task2.id] = task2

        let useCase = GetTemplateWithTasksUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo
        )

        let result = try useCase.execute(templateId: template.id)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.template.name, "Feature Development")
        XCTAssertEqual(result?.tasks.count, 2)
    }
}
