import { http, HttpResponse } from 'msw'

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

    return HttpResponse.json(
      { message: '認証に失敗しました' },
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

  // Tasks
  http.get('/api/projects/:projectId/tasks', () => {
    return HttpResponse.json([
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
    ])
  }),

  // Assignable agents
  http.get('/api/agents/assignable', () => {
    return HttpResponse.json([
      {
        id: 'manager-1',
        name: 'Manager A',
        role: 'Backend Manager',
        agentType: 'ai',
        status: 'active',
        hierarchyType: 'manager',
        parentId: 'owner-1',
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
]
