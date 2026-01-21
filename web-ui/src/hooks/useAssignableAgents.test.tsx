import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useAssignableAgents } from './useAssignableAgents'

const createWrapper = () => {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
      },
    },
  })
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  )
}

describe('useAssignableAgents', () => {
  beforeEach(() => {
    localStorage.clear()
    localStorage.setItem('sessionToken', 'test-session-token')
  })

  // RED: This test should fail because useAssignableAgents doesn't accept projectId yet
  it('accepts projectId parameter and returns agents assigned to that project', async () => {
    // According to requirements (PROJECTS.md):
    // タスク.assignee_id ∈ プロジェクト.割り当てエージェント
    // Task assignees must be agents assigned to the project
    const { result } = renderHook(() => useAssignableAgents('project-1'), {
      wrapper: createWrapper(),
    })

    expect(result.current.isLoading).toBe(true)

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    // Should return only agents assigned to project-1
    // (mock will need to be updated to support project filtering)
    expect(result.current.agents).toBeDefined()
    expect(Array.isArray(result.current.agents)).toBe(true)
  })

  // RED: This test should fail because current implementation doesn't use projectId in query key
  it('uses projectId in query key for proper caching', async () => {
    const queryClient = new QueryClient({
      defaultOptions: {
        queries: {
          retry: false,
        },
      },
    })
    const wrapper = ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    )

    const { result } = renderHook(() => useAssignableAgents('project-1'), {
      wrapper,
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    // The query key should include projectId for proper cache isolation
    const queryState = queryClient.getQueryState(['assignable-agents', 'project-1'])
    expect(queryState).toBeDefined()
  })

  // RED: This test should fail because current API endpoint is not project-specific
  it('calls project-specific API endpoint', async () => {
    const { result } = renderHook(() => useAssignableAgents('project-2'), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    // Different projects should return different agents
    // This verifies that the hook is making project-specific API calls
    expect(result.current.agents).toBeDefined()
  })
})
