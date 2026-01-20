import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, waitFor, act } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useAgent, useUpdateAgent } from './useAgent'

const createWrapper = () => {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
      },
      mutations: {
        retry: false,
      },
    },
  })
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  )
}

describe('useAgent', () => {
  beforeEach(() => {
    localStorage.clear()
    localStorage.setItem('sessionToken', 'test-session-token')
  })

  it('can fetch agent details', async () => {
    const { result } = renderHook(() => useAgent('worker-1'), {
      wrapper: createWrapper(),
    })

    expect(result.current.isLoading).toBe(true)

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(result.current.agent).toBeDefined()
    expect(result.current.agent?.id).toBe('worker-1')
    expect(result.current.agent?.name).toBe('Worker 1')
  })

  it('includes detail fields', async () => {
    const { result } = renderHook(() => useAgent('worker-1'), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    const agent = result.current.agent!
    expect(agent.roleType).toBe('general')
    expect(agent.maxParallelTasks).toBe(3)
    expect(agent.capabilities).toContain('coding')
    expect(agent.systemPrompt).toBe('You are a backend developer.')
    expect(agent.kickMethod).toBe('mcp')
    expect(agent.provider).toBe('anthropic')
    expect(agent.modelId).toBe('claude-3-sonnet')
    expect(agent.isLocked).toBe(false)
    expect(agent.createdAt).toBeDefined()
    expect(agent.updatedAt).toBeDefined()
  })

  it('does not execute query when agentId is null', async () => {
    const { result } = renderHook(() => useAgent(null), {
      wrapper: createWrapper(),
    })

    // Should not be loading since query is disabled
    expect(result.current.isLoading).toBe(false)
    expect(result.current.agent).toBeUndefined()
  })

  it('returns error for non-existent agent', async () => {
    const { result } = renderHook(() => useAgent('unknown-agent'), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(result.current.error).toBeTruthy()
  })

  it('returns error state on authentication error', async () => {
    localStorage.removeItem('sessionToken')

    const { result } = renderHook(() => useAgent('worker-1'), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(result.current.error).toBeTruthy()
  })
})

describe('useUpdateAgent', () => {
  beforeEach(() => {
    localStorage.clear()
    localStorage.setItem('sessionToken', 'test-session-token')
  })

  it('can update agent', async () => {
    const { result } = renderHook(() => useUpdateAgent(), {
      wrapper: createWrapper(),
    })

    await act(async () => {
      result.current.mutate({
        agentId: 'worker-1',
        data: { name: 'Updated Worker' },
      })
    })

    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true)
    })

    expect(result.current.data?.name).toBe('Updated Worker')
  })

  it('can update multiple fields at once', async () => {
    const { result } = renderHook(() => useUpdateAgent(), {
      wrapper: createWrapper(),
    })

    await act(async () => {
      result.current.mutate({
        agentId: 'worker-1',
        data: {
          name: 'New Name',
          role: 'New Role',
          maxParallelTasks: 5,
        },
      })
    })

    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true)
    })

    expect(result.current.data?.name).toBe('New Name')
    expect(result.current.data?.role).toBe('New Role')
    expect(result.current.data?.maxParallelTasks).toBe(5)
  })

  it('returns error when updating locked agent', async () => {
    const { result } = renderHook(() => useUpdateAgent(), {
      wrapper: createWrapper(),
    })

    await act(async () => {
      result.current.mutate({
        agentId: 'worker-locked',
        data: { name: 'Should Fail' },
      })
    })

    await waitFor(() => {
      expect(result.current.isError).toBe(true)
    })

    expect(result.current.error?.message).toContain('locked')
  })
})
