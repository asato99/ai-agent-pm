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

  it('initial state is unauthenticated', () => {
    const { result } = renderHook(() => useAuth())

    expect(result.current.isAuthenticated).toBe(false)
    expect(result.current.agent).toBeNull()
  })

  it('saves session on successful login', async () => {
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

  it('returns error on login failure', async () => {
    const { result } = renderHook(() => useAuth())

    await act(async () => {
      await result.current.login('invalid', 'wrong')
    })

    await waitFor(() => {
      expect(result.current.error).toBe('Authentication failed')
    })
    expect(result.current.isAuthenticated).toBe(false)
  })

  it('clears session on logout', async () => {
    const { result } = renderHook(() => useAuth())

    // First login
    await act(async () => {
      await result.current.login('manager-1', 'test-passkey')
    })

    await waitFor(() => {
      expect(result.current.isAuthenticated).toBe(true)
    })

    // Logout
    await act(async () => {
      await result.current.logout()
    })

    await waitFor(() => {
      expect(result.current.isAuthenticated).toBe(false)
    })
    expect(result.current.agent).toBeNull()
    expect(localStorage.getItem('sessionToken')).toBeNull()
  })

  it('isLoading is true while logging in', async () => {
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
