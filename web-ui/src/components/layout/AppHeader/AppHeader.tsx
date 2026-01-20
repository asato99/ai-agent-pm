import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'

export function AppHeader() {
  const navigate = useNavigate()
  const { agent, logout } = useAuth()

  const handleLogout = async () => {
    await logout()
    navigate('/login', { replace: true })
  }

  return (
    <header className="bg-white shadow">
      <div className="max-w-7xl mx-auto py-4 px-4 sm:px-6 lg:px-8 flex justify-between items-center">
        <h1 className="text-xl font-bold text-gray-900">AI Agent PM</h1>
        <div className="flex items-center gap-4">
          <span className="text-gray-700">{agent?.name}</span>
          <button
            onClick={handleLogout}
            className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700"
          >
            Log out
          </button>
        </div>
      </div>
    </header>
  )
}
