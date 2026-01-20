import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useSubordinates } from './useSubordinates'

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

describe('useSubordinates', () => {
  beforeEach(() => {
    localStorage.clear()
    localStorage.setItem('sessionToken', 'test-session-token')
  })

  it('can fetch subordinate agents list', async () => {
    const { result } = renderHook(() => useSubordinates(), {
      wrapper: createWrapper(),
    })

    expect(result.current.isLoading).toBe(true)

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(result.current.subordinates).toHaveLength(2)
    expect(result.current.subordinates[0].name).toBe('Worker 1')
    expect(result.current.subordinates[1].name).toBe('Worker 2')
  })

  it('includes required fields in agent information', async () => {
    const { result } = renderHook(() => useSubordinates(), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    const agent = result.current.subordinates[0]
    expect(agent.id).toBe('worker-1')
    expect(agent.role).toBe('Backend Developer')
    expect(agent.agentType).toBe('ai')
    expect(agent.status).toBe('active')
    expect(agent.hierarchyType).toBe('worker')
    expect(agent.parentAgentId).toBe('manager-1')
  })

  it('includes agents with different statuses', async () => {
    const { result } = renderHook(() => useSubordinates(), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    const statuses = result.current.subordinates.map((a) => a.status)
    expect(statuses).toContain('active')
    expect(statuses).toContain('inactive')
  })

  it('returns error state on error', async () => {
    localStorage.removeItem('sessionToken')

    const { result } = renderHook(() => useSubordinates(), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(result.current.error).toBeTruthy()
  })
})
