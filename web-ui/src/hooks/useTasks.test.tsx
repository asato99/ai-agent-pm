import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useTasks } from './useTasks'

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

describe('useTasks', () => {
  beforeEach(() => {
    localStorage.clear()
    localStorage.setItem('sessionToken', 'test-session-token')
  })

  it('can fetch project task list', async () => {
    const { result } = renderHook(() => useTasks('project-1'), {
      wrapper: createWrapper(),
    })

    expect(result.current.isLoading).toBe(true)

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(result.current.tasks).toHaveLength(2)
    expect(result.current.tasks[0].title).toBe('API実装')
    expect(result.current.tasks[1].title).toBe('DB設計')
  })

  it('includes status and priority in task information', async () => {
    const { result } = renderHook(() => useTasks('project-1'), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    const apiTask = result.current.tasks[0]
    expect(apiTask.status).toBe('in_progress')
    expect(apiTask.priority).toBe('high')
  })

  it('can get tasks grouped by status', async () => {
    const { result } = renderHook(() => useTasks('project-1'), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    const grouped = result.current.tasksByStatus
    expect(grouped.in_progress).toHaveLength(1)
    expect(grouped.done).toHaveLength(1)
  })
})
