// web-ui/src/hooks/useUnreadCounts.test.tsx
// TDD RED: useUnreadCounts hookのテスト
// Reference: docs/design/CHAT_FEATURE.md - Unread count feature

import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useUnreadCounts } from './useUnreadCounts'

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

describe('useUnreadCounts', () => {
  beforeEach(() => {
    localStorage.clear()
    localStorage.setItem('sessionToken', 'test-session-token')
  })

  describe('未読カウント取得', () => {
    it('プロジェクト内のエージェントごとの未読数を取得できる', async () => {
      const { result } = renderHook(
        () => useUnreadCounts('project-1'),
        { wrapper: createWrapper() }
      )

      expect(result.current.isLoading).toBe(true)

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // MSWモックでproject-1は worker-1:3, worker-2:1 を返す
      expect(result.current.unreadCounts).toBeDefined()
      expect(result.current.unreadCounts['worker-1']).toBe(3)
      expect(result.current.unreadCounts['worker-2']).toBe(1)
    })

    it('未読がない場合は空のオブジェクトを返す', async () => {
      const { result } = renderHook(
        () => useUnreadCounts('project-2'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // MSWモックでproject-2は空のcountsを返す
      expect(result.current.unreadCounts).toEqual({})
    })

    it('特定エージェントの未読数をgetCountForで取得できる', async () => {
      const { result } = renderHook(
        () => useUnreadCounts('project-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.getCountFor('worker-1')).toBe(3)
      expect(result.current.getCountFor('worker-2')).toBe(1)
      expect(result.current.getCountFor('unknown-agent')).toBe(0) // 存在しないエージェントは0
    })

    it('合計未読数をtotalUnreadで取得できる', async () => {
      const { result } = renderHook(
        () => useUnreadCounts('project-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.totalUnread).toBe(4) // 3 + 1
    })
  })

  describe('エラーハンドリング', () => {
    it('無効なプロジェクトIDでエラーが発生する', async () => {
      const { result } = renderHook(
        () => useUnreadCounts('invalid-project'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.error).toBeDefined()
    })

    it('認証なしの場合はエラーになる', async () => {
      localStorage.removeItem('sessionToken')

      const { result } = renderHook(
        () => useUnreadCounts('project-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.error).toBeDefined()
    })
  })

  describe('refetch', () => {
    it('refetchで手動更新ができる', async () => {
      const { result } = renderHook(
        () => useUnreadCounts('project-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      await result.current.refetch()

      expect(result.current.error).toBeNull()
      expect(result.current.unreadCounts).toBeDefined()
    })
  })
})
