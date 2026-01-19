import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'

export function ProjectListPage() {
  const navigate = useNavigate()
  const { agent, logout } = useAuth()

  const handleLogout = async () => {
    await logout()
    navigate('/login', { replace: true })
  }

  return (
    <div className="min-h-screen bg-gray-100">
      <header className="bg-white shadow">
        <div className="max-w-7xl mx-auto py-4 px-4 sm:px-6 lg:px-8 flex justify-between items-center">
          <h1 className="text-xl font-bold text-gray-900">AI Agent PM</h1>
          <div className="flex items-center gap-4">
            <span className="text-gray-700">{agent?.name}</span>
            <button
              onClick={handleLogout}
              className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700"
            >
              ログアウト
            </button>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <h2 className="text-2xl font-bold text-gray-900 mb-6">参加プロジェクト</h2>

        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {/* TODO: プロジェクト一覧を表示 */}
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-gray-500">プロジェクトを読み込み中...</p>
          </div>
        </div>
      </main>
    </div>
  )
}
