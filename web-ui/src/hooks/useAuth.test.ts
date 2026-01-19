import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import { useAuth } from './useAuth'
import { useAuthStore } from '@/stores/authStore'

describe('useAuth', () => {
  beforeEach(() => {
    localStorage.clear()
    // Reset Zustand store state
    useAuthStore.setState({
      isAuthenticated: false,
      agent: null,
      sessionToken: null,
    })
  })

  it('初期状態は未認証', () => {
    const { result } = renderHook(() => useAuth())

    expect(result.current.isAuthenticated).toBe(false)
    expect(result.current.agent).toBeNull()
  })

  it('ログイン成功時にセッションを保存する', async () => {
    const { result } = renderHook(() => useAuth())

    await act(async () => {
      await result.current.login('manager-1', 'test-passkey')
    })

    await waitFor(() => {
      expect(result.current.isAuthenticated).toBe(true)
    })
    expect(result.current.agent?.id).toBe('manager-1')
    expect(result.current.agent?.name).toBe('Manager A')
    expect(localStorage.getItem('sessionToken')).toBe('test-session-token')
  })

  it('ログイン失敗時にエラーを返す', async () => {
    const { result } = renderHook(() => useAuth())

    await act(async () => {
      await result.current.login('invalid', 'wrong')
    })

    await waitFor(() => {
      expect(result.current.error).toBe('認証に失敗しました')
    })
    expect(result.current.isAuthenticated).toBe(false)
  })

  it('ログアウト時にセッションをクリアする', async () => {
    const { result } = renderHook(() => useAuth())

    // まずログイン
    await act(async () => {
      await result.current.login('manager-1', 'test-passkey')
    })

    await waitFor(() => {
      expect(result.current.isAuthenticated).toBe(true)
    })

    // ログアウト
    await act(async () => {
      await result.current.logout()
    })

    await waitFor(() => {
      expect(result.current.isAuthenticated).toBe(false)
    })
    expect(result.current.agent).toBeNull()
    expect(localStorage.getItem('sessionToken')).toBeNull()
  })

  it('ログイン中はisLoadingがtrue', async () => {
    const { result } = renderHook(() => useAuth())

    let loginPromise: Promise<void>
    act(() => {
      loginPromise = result.current.login('manager-1', 'test-passkey')
    })

    expect(result.current.isLoading).toBe(true)

    await act(async () => {
      await loginPromise
    })

    expect(result.current.isLoading).toBe(false)
  })
})
