import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useProjects } from './useProjects'

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

describe('useProjects', () => {
  beforeEach(() => {
    localStorage.clear()
    localStorage.setItem('sessionToken', 'test-session-token')
  })

  it('プロジェクト一覧を取得できる', async () => {
    const { result } = renderHook(() => useProjects(), {
      wrapper: createWrapper(),
    })

    expect(result.current.isLoading).toBe(true)

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(result.current.projects).toHaveLength(2)
    expect(result.current.projects[0].name).toBe('ECサイト開発')
    expect(result.current.projects[1].name).toBe('モバイルアプリ')
  })

  it('プロジェクト情報にタスク数が含まれる', async () => {
    const { result } = renderHook(() => useProjects(), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    const ecProject = result.current.projects[0]
    expect(ecProject.taskCount).toBe(12)
    expect(ecProject.myTaskCount).toBe(3)
    expect(ecProject.completedCount).toBe(5)
  })

  it('アクティブなプロジェクトのみをフィルタできる', async () => {
    const { result } = renderHook(() => useProjects({ status: 'active' }), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(result.current.projects.every((p) => p.status === 'active')).toBe(true)
  })

  it('エラー時にエラー状態を返す', async () => {
    localStorage.removeItem('sessionToken')

    const { result } = renderHook(() => useProjects(), {
      wrapper: createWrapper(),
    })

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(result.current.error).toBeTruthy()
  })
})
