import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ProjectListPage } from './ProjectListPage'
import { useAuthStore } from '@/stores/authStore'

const mockNavigate = vi.fn()

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom')
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  }
})

const createTestQueryClient = () =>
  new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
      },
    },
  })

const renderWithProviders = (component: React.ReactNode) => {
  const queryClient = createTestQueryClient()
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>{component}</MemoryRouter>
    </QueryClientProvider>
  )
}

describe('ProjectListPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    localStorage.clear()
    localStorage.setItem('sessionToken', 'test-session-token')
    useAuthStore.setState({
      isAuthenticated: true,
      agent: {
        id: 'manager-1',
        name: 'Manager A',
        role: 'Backend Manager',
        agentType: 'ai',
        status: 'active',
        hierarchyType: 'manager',
        parentId: 'owner-1',
      },
      sessionToken: 'test-session-token',
    })
  })

  it('displays the page title', async () => {
    renderWithProviders(<ProjectListPage />)

    await waitFor(() => {
      expect(screen.getByText('My Projects')).toBeInTheDocument()
    })
  })

  it('displays spinner while loading', () => {
    renderWithProviders(<ProjectListPage />)

    expect(screen.getByText('Loading projects...')).toBeInTheDocument()
  })

  it('displays project list', async () => {
    renderWithProviders(<ProjectListPage />)

    await waitFor(() => {
      expect(screen.getByText('ECサイト開発')).toBeInTheDocument()
      expect(screen.getByText('モバイルアプリ')).toBeInTheDocument()
    })
  })

  it('navigates to task board when project card is clicked', async () => {
    renderWithProviders(<ProjectListPage />)

    await waitFor(() => {
      expect(screen.getByText('ECサイト開発')).toBeInTheDocument()
    })

    fireEvent.click(screen.getAllByTestId('project-card')[0])

    expect(mockNavigate).toHaveBeenCalledWith('/projects/project-1')
  })

  it('displays agent name in header', async () => {
    renderWithProviders(<ProjectListPage />)

    await waitFor(() => {
      expect(screen.getByText('Manager A')).toBeInTheDocument()
    })
  })

  it('displays logout button', async () => {
    renderWithProviders(<ProjectListPage />)

    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Log out' })).toBeInTheDocument()
    })
  })
})
