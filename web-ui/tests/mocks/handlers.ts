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
    assigneeId: null,
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
              sender: 'user',
              content: 'こんにちは',
              createdAt: '2024-01-15T10:00:00Z',
            },
            {
              id: 'msg-2',
              sender: 'agent',
              content: 'こんにちは！何かお手伝いできますか？',
              createdAt: '2024-01-15T10:01:00Z',
            },
          ],
          hasMore: false,
          totalCount: 2,
        })
      }
      // worker-2 has no messages
      if (agentId === 'worker-2') {
        return HttpResponse.json({
          messages: [],
          hasMore: false,
          totalCount: 0,
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
        sender: 'user',
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
]
