import { useNavigate } from 'react-router-dom'
import { useSubordinates } from '@/hooks'
import { AgentCard } from '../AgentCard'

export function AgentListSection() {
  const navigate = useNavigate()
  const { subordinates, isLoading, error } = useSubordinates()

  const handleAgentClick = (agentId: string) => {
    navigate(`/agents/${agentId}`)
  }

  return (
    <section className="mt-12">
      <h2 className="text-2xl font-bold text-gray-900 mb-6">部下エージェント</h2>

      <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
        {isLoading && (
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-gray-500">エージェントを読み込み中...</p>
          </div>
        )}

        {error && (
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-red-500">エラーが発生しました: {error.message}</p>
          </div>
        )}

        {!isLoading &&
          !error &&
          subordinates.map((agent) => (
            <AgentCard key={agent.id} agent={agent} onClick={handleAgentClick} />
          ))}

        {!isLoading && !error && subordinates.length === 0 && (
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-gray-500">部下エージェントはいません</p>
          </div>
        )}
      </div>
    </section>
  )
}
