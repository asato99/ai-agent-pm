import { http, HttpResponse } from 'msw'

interface Task {
  id: string
  projectId: string
  title: string
  description: string
  status: string
  priority: string
  assigneeId: string | null
  creatorId: string
  parentTaskId: string | null
  dependencies: string[]
  dependentTasks: string[]
  blockedReason: string | null
  estimatedMinutes: number | null
  actualMinutes: number | null
  contexts: unknown[]
  createdAt: string
  updatedAt: string
}

// In-memory task store for E2E tests
// Includes hierarchy test data: root → child → grandchild
const initialTasks: Task[] = [
  // Root task (L0)
  {
    id: 'task-1',
    projectId: 'project-1',
    title: 'API実装',
    description: 'REST APIエンドポイントの実装',
    status: 'in_progress',
    priority: 'high',
    assigneeId: 'worker-1',
    creatorId: 'manager-1',
    parentTaskId: null,
    dependencies: ['task-2'],  // depends on DB設計
    dependentTasks: ['task-3'],  // task-3 depends on this
    blockedReason: null,
    estimatedMinutes: 480,
    actualMinutes: 240,
    contexts: [],
    createdAt: '2024-01-10T00:00:00Z',
    updatedAt: '2024-01-15T10:00:00Z',
  },
  // Done task (L0)
  {
    id: 'task-2',
    projectId: 'project-1',
    title: 'DB設計',
    description: 'データベーススキーマの設計',
    status: 'done',
    priority: 'medium',
    assigneeId: null,
    creatorId: 'manager-1',
    parentTaskId: null,
    dependencies: [],
    dependentTasks: ['task-1'],
    blockedReason: null,
    estimatedMinutes: 120,
    actualMinutes: 90,
    contexts: [],
    createdAt: '2024-01-08T00:00:00Z',
    updatedAt: '2024-01-12T14:00:00Z',
  },
  // Child task (L1) - child of task-1
  {
    id: 'task-3',
    projectId: 'project-1',
    title: 'エンドポイント実装',
    description: 'APIエンドポイントの実装詳細',
    status: 'todo',
    priority: 'high',
    assigneeId: null,
    creatorId: 'manager-1',
    parentTaskId: 'task-1',
    dependencies: ['task-1'],
    dependentTasks: ['task-4'],
    blockedReason: null,
    estimatedMinutes: 240,
    actualMinutes: null,
    contexts: [],
    createdAt: '2024-01-11T00:00:00Z',
    updatedAt: '2024-01-11T00:00:00Z',
  },
  // Grandchild task (L2) - child of task-3
  {
    id: 'task-4',
    projectId: 'project-1',
    title: 'ユーザーAPI',
    description: 'ユーザー管理APIの実装',
    status: 'backlog',
    priority: 'medium',
    assigneeId: null,
    creatorId: 'manager-1',
    parentTaskId: 'task-3',
    dependencies: ['task-3'],
    dependentTasks: [],
    blockedReason: null,
    estimatedMinutes: 120,
    actualMinutes: null,
    contexts: [],
    createdAt: '2024-01-12T00:00:00Z',
    updatedAt: '2024-01-12T00:00:00Z',
  },
  // Blocked task (L0)
  {
    id: 'task-5',
    projectId: 'project-1',
    title: 'フロントエンド実装',
    description: 'フロントエンドUIの実装',
    status: 'blocked',
    priority: 'high',
    assigneeId: 'worker-2',
    creatorId: 'manager-1',
    parentTaskId: null,
    dependencies: ['task-1', 'task-3'],
    dependentTasks: [],
    blockedReason: 'API実装の完了待ち',
    estimatedMinutes: 480,
    actualMinutes: null,
    contexts: [],
    createdAt: '2024-01-13T00:00:00Z',
    updatedAt: '2024-01-13T00:00:00Z',
  },
]

let tasks: Task[] = [...initialTasks]

// Phase 2.4: In-memory working directory store for E2E tests
const projectWorkingDirectories = new Map<string, string>()

// Reset tasks to initial state (call between tests)
export function resetMockTasks() {
  tasks = [...initialTasks]
  projectWorkingDirectories.clear()
}

export const handlers = [
  // Auth
  http.post('/api/auth/login', async ({ request }) => {
    const body = (await request.json()) as { agentId: string; passkey: string }

    if (body.agentId === 'manager-1' && body.passkey === 'test-passkey') {
      return HttpResponse.json({
        sessionToken: 'test-session-token',
        agent: {
          id: 'manager-1',
          name: 'Manager A',
          role: 'Backend Manager',
          agentType: 'ai',
          status: 'active',
          hierarchyType: 'manager',
          parentId: 'owner-1',
        },
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      })
    }

    if (body.agentId === 'owner-1' && body.passkey === 'test-passkey') {
      return HttpResponse.json({
        sessionToken: 'test-session-token-owner',
        agent: {
          id: 'owner-1',
          name: 'Owner',
          role: 'Project Owner',
          agentType: 'human',
          status: 'active',
          hierarchyType: 'owner',
          parentId: null,
        },
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      })
    }

    return HttpResponse.json(
      { message: 'Authentication failed' },
      { status: 401 }
    )
  }),

  http.post('/api/auth/logout', () => {
    return HttpResponse.json({ success: true })
  }),

  http.get('/api/auth/me', ({ request }) => {
    const authHeader = request.headers.get('Authorization')
    if (authHeader === 'Bearer test-session-token') {
      return HttpResponse.json({
        id: 'manager-1',
        name: 'Manager A',
        role: 'Backend Manager',
        agentType: 'ai',
        status: 'active',
        hierarchyType: 'manager',
        parentId: 'owner-1',
      })
    }
    if (authHeader === 'Bearer test-session-token-owner') {
      return HttpResponse.json({
        id: 'owner-1',
        name: 'Owner',
        role: 'Project Owner',
        agentType: 'human',
        status: 'active',
        hierarchyType: 'owner',
        parentId: null,
      })
    }
    return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
  }),

  // Projects
  http.get('/api/projects', ({ request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    return HttpResponse.json([
      {
        id: 'project-1',
        name: 'ECサイト開発',
        description: 'ECサイトの新規開発プロジェクト',
        status: 'active',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-15T10:00:00Z',
        taskCount: 12,
        completedCount: 5,
        inProgressCount: 3,
        blockedCount: 1,
        myTaskCount: 3,
      },
      {
        id: 'project-2',
        name: 'モバイルアプリ',
        description: 'iOSアプリ開発',
        status: 'active',
        createdAt: '2024-01-05T00:00:00Z',
        updatedAt: '2024-01-14T15:00:00Z',
        taskCount: 8,
        completedCount: 7,
        inProgressCount: 1,
        blockedCount: 0,
        myTaskCount: 1,
      },
    ])
  }),

  // Project detail
  http.get('/api/projects/:projectId', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId } = params
    if (projectId === 'project-1') {
      // Check if there's a working directory set for this project
      const workingDir = projectWorkingDirectories.get(projectId as string)
      return HttpResponse.json({
        id: 'project-1',
        name: 'ECサイト開発',
        description: 'ECサイトの新規開発プロジェクト',
        status: 'active',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-15T10:00:00Z',
        taskCount: 12,
        completedCount: 5,
        inProgressCount: 3,
        blockedCount: 1,
        myTaskCount: 3,
        myWorkingDirectory: workingDir || null,
      })
    }
    return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
  }),

  // Phase 2.4: Set working directory
  http.put('/api/projects/:projectId/my-working-directory', async ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId } = params
    const body = (await request.json()) as { workingDirectory: string }
    projectWorkingDirectories.set(projectId as string, body.workingDirectory)
    return HttpResponse.json({ workingDirectory: body.workingDirectory })
  }),

  // Phase 2.4: Delete working directory
  http.delete('/api/projects/:projectId/my-working-directory', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId } = params
    projectWorkingDirectories.delete(projectId as string)
    return new HttpResponse(null, { status: 204 })
  }),

  // Tasks - returns dynamic task list
  http.get('/api/projects/:projectId/tasks', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId } = params
    const projectTasks = tasks.filter(t => t.projectId === projectId)
    return HttpResponse.json(projectTasks)
  }),

  // Create task - adds to dynamic task list
  http.post('/api/projects/:projectId/tasks', async ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const body = (await request.json()) as {
      title: string
      description?: string
      priority?: string
    }
    const { projectId } = params
    const newTask: Task = {
      id: `task-${Date.now()}`,
      projectId: projectId as string,
      title: body.title,
      description: body.description || '',
      status: 'backlog',
      priority: body.priority || 'medium',
      assigneeId: null,
      creatorId: 'manager-1',
      parentTaskId: null,
      dependencies: [],
      dependentTasks: [],
      blockedReason: null,
      estimatedMinutes: null,
      actualMinutes: null,
      contexts: [],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }
    tasks.push(newTask)
    return HttpResponse.json(newTask)
  }),

  // Get task permissions
  http.get('/api/tasks/:taskId/permissions', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { taskId } = params
    const task = tasks.find(t => t.id === taskId)
    if (!task) {
      return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
    }

    // Return permissions - for mock, allow all edits
    const canReassign = task.status !== 'in_progress' && task.status !== 'blocked'
    const allStatuses = ['backlog', 'todo', 'in_progress', 'blocked', 'done', 'cancelled']

    return HttpResponse.json({
      canEdit: true,
      canChangeStatus: true,
      canReassign: canReassign,
      validStatusTransitions: allStatuses,
      reason: canReassign ? null : `Task is ${task.status}, reassignment disabled`,
    })
  }),

  // Get task handoffs
  http.get('/api/tasks/:taskId/handoffs', ({ request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    // Return empty handoffs for mock
    return HttpResponse.json([])
  }),

  // Update task status
  http.patch('/api/tasks/:taskId', async ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const body = (await request.json()) as {
      status?: string
      title?: string
      description?: string
      priority?: string
      assigneeId?: string | null
    }
    const { taskId } = params
    const task = tasks.find(t => t.id === taskId)
    if (!task) {
      return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
    }
    // Update all provided fields
    if (body.status !== undefined) {
      task.status = body.status
    }
    if (body.title !== undefined) {
      task.title = body.title
    }
    if (body.description !== undefined) {
      task.description = body.description
    }
    if (body.priority !== undefined) {
      task.priority = body.priority
    }
    if (body.assigneeId !== undefined) {
      task.assigneeId = body.assigneeId
    }
    task.updatedAt = new Date().toISOString()
    return HttpResponse.json(task)
  }),

  // Delete task (logical deletion - sets status to 'cancelled')
  http.delete('/api/tasks/:taskId', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { taskId } = params
    const task = tasks.find(t => t.id === taskId)
    if (!task) {
      return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
    }
    // Logical deletion: set status to 'cancelled'
    task.status = 'cancelled'
    task.updatedAt = new Date().toISOString()
    return new HttpResponse(null, { status: 204 })
  }),

  // Agent sessions (active session counts per agent, by purpose)
  // 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md
  http.get('/api/projects/:projectId/agent-sessions', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId } = params

    if (projectId === 'project-1') {
      return HttpResponse.json({
        agentSessions: {
          'worker-1': { chat: 1, task: 0 },  // has active chat session
          'worker-2': { chat: 0, task: 0 },  // no sessions
        },
      })
    }
    if (projectId === 'project-2') {
      return HttpResponse.json({
        agentSessions: {
          'worker-2': { chat: 0, task: 0 },
        },
      })
    }
    return HttpResponse.json({ agentSessions: {} })
  }),

  // Assignable agents (project-specific)
  // According to requirements (PROJECTS.md): Task assignees must be agents assigned to the project
  http.get('/api/projects/:projectId/assignable-agents', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId } = params

    // Mock: project-1 has worker-1 and worker-2 assigned
    // project-2 has only worker-2 assigned
    if (projectId === 'project-1') {
      return HttpResponse.json([
        {
          id: 'worker-1',
          name: 'Worker 1',
          role: 'Backend Developer',
          agentType: 'ai',
          status: 'active',
          hierarchyType: 'worker',
          parentId: 'manager-1',
        },
        {
          id: 'worker-2',
          name: 'Worker 2',
          role: 'Frontend Developer',
          agentType: 'ai',
          status: 'active',
          hierarchyType: 'worker',
          parentId: 'manager-1',
        },
      ])
    }
    if (projectId === 'project-2') {
      return HttpResponse.json([
        {
          id: 'worker-2',
          name: 'Worker 2',
          role: 'Frontend Developer',
          agentType: 'ai',
          status: 'active',
          hierarchyType: 'worker',
          parentId: 'manager-1',
        },
      ])
    }
    return HttpResponse.json([])
  }),

  // Legacy endpoint (kept for backward compatibility, will be deprecated)
  http.get('/api/agents/assignable', () => {
    return HttpResponse.json([
      {
        id: 'manager-1',
        name: 'Manager A',
        role: 'Backend Manager',
        agentType: 'ai',
        status: 'active',
        hierarchyType: 'manager',
        parentId: null,  // Top-level manager has no parent
      },
      {
        id: 'worker-1',
        name: 'Worker 1',
        role: 'Backend Developer',
        agentType: 'ai',
        status: 'active',
        hierarchyType: 'worker',
        parentId: 'manager-1',
      },
      {
        id: 'worker-2',
        name: 'Worker 2',
        role: 'Frontend Developer',
        agentType: 'ai',
        status: 'active',
        hierarchyType: 'worker',
        parentId: 'manager-1',
      },
    ])
  }),

  // Subordinate agents
  http.get('/api/agents/subordinates', ({ request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }

    // Owner sees all descendants (manager + workers)
    if (authHeader === 'Bearer test-session-token-owner') {
      return HttpResponse.json([
        {
          id: 'manager-1',
          name: 'Manager A',
          role: 'Backend Manager',
          agentType: 'ai',
          status: 'active',
          hierarchyType: 'manager',
          parentAgentId: 'owner-1',
        },
        {
          id: 'worker-1',
          name: 'Worker 1',
          role: 'Backend Developer',
          agentType: 'ai',
          status: 'active',
          hierarchyType: 'worker',
          parentAgentId: 'manager-1',
        },
        {
          id: 'worker-2',
          name: 'Worker 2',
          role: 'Frontend Developer',
          agentType: 'ai',
          status: 'inactive',
          hierarchyType: 'worker',
          parentAgentId: 'manager-1',
        },
      ])
    }

    // Manager sees only direct subordinates (workers)
    return HttpResponse.json([
      {
        id: 'worker-1',
        name: 'Worker 1',
        role: 'Backend Developer',
        agentType: 'ai',
        status: 'active',
        hierarchyType: 'worker',
        parentAgentId: 'manager-1',
      },
      {
        id: 'worker-2',
        name: 'Worker 2',
        role: 'Frontend Developer',
        agentType: 'ai',
        status: 'inactive',
        hierarchyType: 'worker',
        parentAgentId: 'manager-1',
      },
    ])
  }),

  // Agent detail
  http.get('/api/agents/:agentId', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { agentId } = params
    if (agentId === 'worker-1') {
      return HttpResponse.json({
        id: 'worker-1',
        name: 'Worker 1',
        role: 'Backend Developer',
        agentType: 'ai',
        status: 'active',
        hierarchyType: 'worker',
        parentAgentId: 'manager-1',
        roleType: 'general',
        maxParallelTasks: 3,
        capabilities: ['coding', 'testing'],
        systemPrompt: 'You are a backend developer.',
        kickMethod: 'mcp',
        provider: 'anthropic',
        modelId: 'claude-3-sonnet',
        isLocked: false,
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-15T10:00:00Z',
      })
    }
    if (agentId === 'worker-locked') {
      return HttpResponse.json({
        id: 'worker-locked',
        name: 'Locked Worker',
        role: 'Developer',
        agentType: 'ai',
        status: 'active',
        hierarchyType: 'worker',
        parentAgentId: 'manager-1',
        roleType: 'general',
        maxParallelTasks: 1,
        capabilities: [],
        systemPrompt: null,
        kickMethod: 'cli',
        provider: null,
        modelId: null,
        isLocked: true,
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-15T10:00:00Z',
      })
    }
    if (agentId === 'unknown-agent') {
      return HttpResponse.json({ message: 'Agent not found' }, { status: 404 })
    }
    return HttpResponse.json({ message: 'Forbidden' }, { status: 403 })
  }),

  // Update agent
  http.patch('/api/agents/:agentId', async ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { agentId } = params
    if (agentId === 'worker-locked') {
      return HttpResponse.json({ message: 'Agent is currently locked' }, { status: 423 })
    }
    if (agentId === 'worker-1') {
      const body = (await request.json()) as Record<string, unknown>
      return HttpResponse.json({
        id: 'worker-1',
        name: body.name ?? 'Worker 1',
        role: body.role ?? 'Backend Developer',
        agentType: 'ai',
        status: body.status ?? 'active',
        hierarchyType: 'worker',
        parentAgentId: 'manager-1',
        roleType: 'general',
        maxParallelTasks: body.maxParallelTasks ?? 3,
        capabilities: body.capabilities ?? ['coding', 'testing'],
        systemPrompt: body.systemPrompt ?? 'You are a backend developer.',
        kickMethod: 'mcp',
        provider: 'anthropic',
        modelId: 'claude-3-sonnet',
        isLocked: false,
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: new Date().toISOString(),
      })
    }
    return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
  }),

  // Unread message counts - GET
  // Reference: docs/design/CHAT_FEATURE.md - Unread count feature
  http.get('/api/projects/:projectId/unread-counts', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId } = params

    // Mock unread counts for project-1
    if (projectId === 'project-1') {
      return HttpResponse.json({
        counts: {
          'worker-1': 3,  // 3 unread messages from worker-1
          'worker-2': 1,  // 1 unread message from worker-2
        },
      })
    }

    // project-2 has no unread
    if (projectId === 'project-2') {
      return HttpResponse.json({
        counts: {},
      })
    }

    // Unknown project
    return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
  }),

  // Chat messages - GET
  http.get('/api/projects/:projectId/agents/:agentId/chat/messages', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId, agentId } = params

    // Valid project (project-1) and agents (worker-1, worker-2, agent-1 for unit tests)
    if (projectId === 'project-1') {
      // worker-1 and agent-1 have message history (agent-1 for backward compatibility with unit tests)
      if (agentId === 'worker-1' || agentId === 'agent-1') {
        return HttpResponse.json({
          messages: [
            {
              id: 'msg-1',
              senderId: 'user-1',
              receiverId: agentId,
              content: 'こんにちは',
              createdAt: '2024-01-15T10:00:00Z',
            },
            {
              id: 'msg-2',
              senderId: agentId,
              receiverId: 'user-1',
              content: 'こんにちは！何かお手伝いできますか？',
              createdAt: '2024-01-15T10:01:00Z',
            },
          ],
          hasMore: false,
          totalCount: 2,
          // Agent's last message is the most recent, so no pending messages
          awaitingAgentResponse: false,
        })
      }
      // worker-2 has no messages
      if (agentId === 'worker-2') {
        return HttpResponse.json({
          messages: [],
          hasMore: false,
          totalCount: 0,
          awaitingAgentResponse: false,
        })
      }
    }

    // Invalid project or agent
    return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
  }),

  // Chat messages - POST
  http.post('/api/projects/:projectId/agents/:agentId/chat/messages', async ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId, agentId } = params
    const body = (await request.json()) as { content: string; relatedTaskId?: string }

    // Valid project and agents (agent-1 for backward compatibility with unit tests)
    if (projectId === 'project-1' && (agentId === 'worker-1' || agentId === 'worker-2' || agentId === 'agent-1')) {
      return HttpResponse.json({
        id: `msg-${Date.now()}`,
        senderId: 'user-1',
        receiverId: agentId,
        content: body.content,
        createdAt: new Date().toISOString(),
        relatedTaskId: body.relatedTaskId,
      })
    }

    // Invalid project or agent
    return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
  }),

  // Chat mark-read - POST
  http.post('/api/projects/:projectId/agents/:agentId/chat/mark-read', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId, agentId } = params

    // Valid project and agents
    if (projectId === 'project-1' && (agentId === 'worker-1' || agentId === 'worker-2' || agentId === 'agent-1')) {
      return HttpResponse.json({ success: true })
    }

    // Invalid project or agent
    return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
  }),

  // Chat session start - POST
  // Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Phase 3
  http.post('/api/projects/:projectId/agents/:agentId/chat/start', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId, agentId } = params

    // Valid project and agents
    if (projectId === 'project-1' && (agentId === 'worker-1' || agentId === 'worker-2' || agentId === 'agent-1')) {
      return HttpResponse.json({ success: true })
    }

    // Invalid project or agent
    return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
  }),

  // Chat session end - POST
  // Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6 (UC015)
  http.post('/api/projects/:projectId/agents/:agentId/chat/end', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { projectId, agentId } = params

    // Valid project and agents
    if (projectId === 'project-1' && (agentId === 'worker-1' || agentId === 'worker-2' || agentId === 'agent-1')) {
      // Simulate ending the session
      // In real implementation, this sets session state to 'terminating'
      return HttpResponse.json({ success: true })
    }

    // If no active session, still return success (idempotent)
    return HttpResponse.json({ success: true, noActiveSession: true })
  }),

  // Task Execution Logs - GET
  // Reference: docs/design/TASK_EXECUTION_LOG_DISPLAY.md
  http.get('/api/tasks/:taskId/execution-logs', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { taskId } = params

    // task-1 (API実装) has execution logs
    if (taskId === 'task-1') {
      return HttpResponse.json({
        executionLogs: [
          {
            id: 'log-1',
            taskId: 'task-1',
            agentId: 'worker-1',
            agentName: 'Worker 1',
            status: 'completed',
            startedAt: '2024-01-15T08:00:00Z',
            completedAt: '2024-01-15T08:15:00Z',
            exitCode: 0,
            durationSeconds: 900.5,
            logFilePath: '/logs/task-1/log-1.txt',
            hasLogFile: true,
            errorMessage: null,
            reportedProvider: 'anthropic',
            reportedModel: 'claude-sonnet-4-20250514',
            modelVerified: true,
          },
          {
            id: 'log-2',
            taskId: 'task-1',
            agentId: 'worker-1',
            agentName: 'Worker 1',
            status: 'failed',
            startedAt: '2024-01-15T08:30:00Z',
            completedAt: '2024-01-15T08:35:00Z',
            exitCode: 1,
            durationSeconds: 300.0,
            logFilePath: '/logs/task-1/log-2.txt',
            hasLogFile: true,
            errorMessage: 'Test failure: assertion failed at line 42',
            reportedProvider: 'anthropic',
            reportedModel: 'claude-sonnet-4-20250514',
            modelVerified: true,
          },
          {
            id: 'log-3',
            taskId: 'task-1',
            agentId: 'worker-1',
            agentName: 'Worker 1',
            status: 'running',
            startedAt: '2024-01-15T09:50:00Z',
            completedAt: null,
            exitCode: null,
            durationSeconds: null,
            logFilePath: null,
            hasLogFile: false,
            errorMessage: null,
            reportedProvider: 'anthropic',
            reportedModel: 'claude-sonnet-4-20250514',
            modelVerified: null,
          },
        ],
      })
    }

    // task-2 (DB設計) has no execution logs (for empty state test)
    if (taskId === 'task-2') {
      return HttpResponse.json({ executionLogs: [] })
    }

    // Other tasks return empty array
    return HttpResponse.json({ executionLogs: [] })
  }),

  // Task Contexts - GET
  // Reference: docs/design/TASK_EXECUTION_LOG_DISPLAY.md
  http.get('/api/tasks/:taskId/contexts', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { taskId } = params

    // task-1 (API実装) has contexts
    if (taskId === 'task-1') {
      return HttpResponse.json({
        contexts: [
          {
            id: 'ctx-1',
            taskId: 'task-1',
            sessionId: 'session-1',
            agentId: 'worker-1',
            agentName: 'Worker 1',
            progress: 'エンドポイント設計完了',
            findings: 'REST API設計パターンを採用',
            blockers: null,
            nextSteps: 'コントローラー実装を開始',
            createdAt: '2024-01-15T08:00:00Z',
            updatedAt: '2024-01-15T08:15:00Z',
          },
          {
            id: 'ctx-2',
            taskId: 'task-1',
            sessionId: 'session-2',
            agentId: 'worker-1',
            agentName: 'Worker 1',
            progress: 'コントローラー実装中',
            findings: 'バリデーション層の追加が必要',
            blockers: 'テストデータの準備が必要',
            nextSteps: 'バリデーション実装後、テスト作成',
            createdAt: '2024-01-15T09:00:00Z',
            updatedAt: '2024-01-15T09:30:00Z',
          },
          {
            id: 'ctx-3',
            taskId: 'task-1',
            sessionId: 'session-3',
            agentId: 'manager-1',
            agentName: 'Manager A',
            progress: null,
            findings: null,
            blockers: 'Worker-1のテストデータ待ち',
            nextSteps: 'テストデータ準備を依頼済み',
            createdAt: '2024-01-15T09:40:00Z',
            updatedAt: '2024-01-15T09:40:00Z',
          },
        ],
      })
    }

    // task-2 (DB設計) has no contexts (for empty state test)
    if (taskId === 'task-2') {
      return HttpResponse.json({ contexts: [] })
    }

    // Other tasks return empty array
    return HttpResponse.json({ contexts: [] })
  }),

  // Execution Log Content - GET
  // Reference: docs/design/TASK_EXECUTION_LOG_DISPLAY.md
  http.get('/api/execution-logs/:logId/content', ({ params, request }) => {
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return HttpResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { logId } = params

    // log-1: Completed execution log
    if (logId === 'log-1') {
      return HttpResponse.json({
        content: `[2024-01-15 08:00:00] Starting task execution...
[2024-01-15 08:00:01] Loading project configuration
[2024-01-15 08:00:05] Setting up REST API endpoints
[2024-01-15 08:05:00] Implementing GET /api/users endpoint
[2024-01-15 08:10:00] Implementing POST /api/users endpoint
[2024-01-15 08:14:00] Running tests...
[2024-01-15 08:14:30] All tests passed (15/15)
[2024-01-15 08:15:00] Task completed successfully`,
      })
    }

    // log-2: Failed execution log
    if (logId === 'log-2') {
      return HttpResponse.json({
        content: `[2024-01-15 08:30:00] Starting task execution...
[2024-01-15 08:30:01] Loading project configuration
[2024-01-15 08:32:00] Implementing validation logic
[2024-01-15 08:34:00] Running tests...
[2024-01-15 08:34:55] FAILED: test_user_validation (line 42)
[2024-01-15 08:35:00] Task failed with exit code 1`,
      })
    }

    // log-3: Running (no content yet)
    if (logId === 'log-3') {
      return HttpResponse.json({
        content: `[2024-01-15 09:50:00] Starting task execution...
[2024-01-15 09:50:01] Loading project configuration
[2024-01-15 09:50:05] Processing...`,
      })
    }

    return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
  }),
]
