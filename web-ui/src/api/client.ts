import type { ApiResult } from '@/types'
import { useAuthStore } from '@/stores/authStore'

// API base URL
// - Production (served from same origin): '/api'
// - Development (vite dev server): use VITE_API_PORT env var with CORS
function getApiBase(): string {
  // Only use direct access in development mode
  // import.meta.env.DEV is true when running `npm run dev`, false in production build
  if (import.meta.env.DEV) {
    const viteApiPort = import.meta.env.VITE_API_PORT as string | undefined
    if (viteApiPort) {
      // Development mode: direct access to REST server (with CORS)
      return `http://localhost:${viteApiPort}/api`
    }
  }

  // Production mode: same origin (relative path)
  return '/api'
}

const API_BASE = getApiBase()

interface RequestOptions extends RequestInit {
  params?: Record<string, string>
}

async function request<T>(
  endpoint: string,
  options: RequestOptions = {}
): Promise<ApiResult<T>> {
  const { params, ...init } = options

  let url = `${API_BASE}${endpoint}`
  if (params) {
    const searchParams = new URLSearchParams(params)
    url += `?${searchParams.toString()}`
  }

  const token = localStorage.getItem('sessionToken')
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  }
  if (token) {
    headers['Authorization'] = `Bearer ${token}`
  }
  // Merge with provided headers
  if (init.headers) {
    const providedHeaders = new Headers(init.headers)
    providedHeaders.forEach((value, key) => {
      headers[key] = value
    })
  }

  try {
    const response = await fetch(url, { ...init, headers })

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}))

      // 401 Unauthorized - セッション無効または期限切れの場合は自動ログアウト
      if (response.status === 401) {
        // Zustand store の logout を直接呼び出し
        useAuthStore.getState().logout()
        // ログインページへリダイレクト（現在のページが既にログインページでない場合）
        if (window.location.pathname !== '/login') {
          window.location.href = '/login'
        }
      }

      return {
        error: {
          message: errorData.message || `HTTP ${response.status}`,
          code: errorData.code,
        },
      }
    }

    // Handle 204 No Content responses
    if (response.status === 204) {
      return { data: undefined as T }
    }

    const data = await response.json()
    return { data }
  } catch (error) {
    return {
      error: {
        message: error instanceof Error ? error.message : 'Unknown error',
      },
    }
  }
}

export const api = {
  get: <T>(endpoint: string, params?: Record<string, string>) =>
    request<T>(endpoint, { method: 'GET', params }),

  post: <T>(endpoint: string, body?: unknown) =>
    request<T>(endpoint, {
      method: 'POST',
      body: body ? JSON.stringify(body) : undefined,
    }),

  put: <T>(endpoint: string, body?: unknown) =>
    request<T>(endpoint, {
      method: 'PUT',
      body: body ? JSON.stringify(body) : undefined,
    }),

  patch: <T>(endpoint: string, body?: unknown) =>
    request<T>(endpoint, {
      method: 'PATCH',
      body: body ? JSON.stringify(body) : undefined,
    }),

  delete: <T>(endpoint: string) => request<T>(endpoint, { method: 'DELETE' }),
}
