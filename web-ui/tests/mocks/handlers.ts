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
  dependencies: string[]
  contexts: unknown[]
  createdAt: string
  updatedAt: string
}

// In-memory task store for E2E tests
const initialTasks: Task[] = [
  {
    id: 'task-1',
    projectId: 'project-1',
    title: 'API実装',
    description: 'REST APIエンドポイントの実装',
    status: 'in_progress',
    priority: 'high',
    assigneeId: 'worker-1',
    creatorId: 'manager-1',
    dependencies: [],
    contexts: [],
    createdAt: '2024-01-10T00:00:00Z',
    updatedAt: '2024-01-15T10:00:00Z',
  },
  {
    id: 'task-2',
    projectId: 'project-1',
    title: 'DB設計',
    description: 'データベーススキーマの設計',
    status: 'done',
    priority: 'medium',
    assigneeId: 'worker-2',
    creatorId: 'manager-1',
    dependencies: [],
    contexts: [],
    createdAt: '2024-01-08T00:00:00Z',
    updatedAt: '2024-01-12T14:00:00Z',
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
          parentId: null,  // Top-level manager has no parent
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
        parentId: null,  // Top-level manager has no parent
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
      dependencies: [],
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
    const body = (await request.json()) as { status?: string }
    const { taskId } = params
    const task = tasks.find(t => t.id === taskId)
    if (!task) {
      return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
    }
    if (body.status) {
      task.status = body.status
      task.updatedAt = new Date().toISOString()
    }
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
]
