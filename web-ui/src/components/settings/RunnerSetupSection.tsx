import { useState } from 'react'
import type { AppSettings } from '@/types'

interface Props {
  settings: AppSettings
}

export function RunnerSetupSection({ settings }: Props) {
  const [copied, setCopied] = useState(false)

  const serverUrl = window.location.origin
  const command = `aiagent-runner --coordinator \\
  --server ${serverUrl} \\
  --token <YOUR_COORDINATOR_TOKEN>`

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(
        `aiagent-runner --coordinator --server ${serverUrl} --token <YOUR_COORDINATOR_TOKEN>`
      )
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      // Fallback for non-HTTPS contexts
      const textArea = document.createElement('textarea')
      textArea.value = `aiagent-runner --coordinator --server ${serverUrl} --token <YOUR_COORDINATOR_TOKEN>`
      document.body.appendChild(textArea)
      textArea.select()
      document.execCommand('copy')
      document.body.removeChild(textArea)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }
  }

  return (
    <div className="space-y-6">
      {/* Prerequisites */}
      <div>
        <h3 className="text-sm font-medium text-gray-700 mb-2">Prerequisites</h3>
        <ul className="text-xs text-gray-600 space-y-1 list-disc list-inside">
          <li>Python 3.9+ installed</li>
          <li>
            <code className="bg-gray-100 px-1 rounded">pip install aiagent-runner[http]</code>
          </li>
          <li>Coordinator token generated (see Coordinator tab)</li>
          <li>Remote access enabled if running from a different machine</li>
        </ul>
      </div>

      {/* Token Warning */}
      {!settings.coordinatorTokenSet && (
        <div className="p-3 bg-yellow-50 border border-yellow-200 rounded text-sm text-yellow-700">
          No coordinator token is configured. Generate one in the Coordinator tab before running the command.
        </div>
      )}

      {/* Command */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">
          Runner Start Command
        </label>
        <div className="relative">
          <pre className="bg-gray-900 text-green-400 text-sm p-4 rounded-lg overflow-x-auto">
            {command}
          </pre>
          <button
            onClick={handleCopy}
            className="absolute top-2 right-2 px-2 py-1 text-xs font-medium text-gray-300 bg-gray-700 rounded hover:bg-gray-600"
          >
            {copied ? 'Copied!' : 'Copy'}
          </button>
        </div>
        <p className="text-xs text-gray-500 mt-2">
          Replace <code className="bg-gray-100 px-1 rounded">&lt;YOUR_COORDINATOR_TOKEN&gt;</code> with
          the actual token from the Coordinator tab.
        </p>
      </div>

      {/* With root-agent-id */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">
          With Root Agent ID (multi-device)
        </label>
        <pre className="bg-gray-900 text-green-400 text-sm p-4 rounded-lg overflow-x-auto">
{`aiagent-runner --coordinator \\
  --server ${serverUrl} \\
  --token <YOUR_COORDINATOR_TOKEN> \\
  --root-agent-id <AGENT_ID>`}
        </pre>
        <p className="text-xs text-gray-500 mt-2">
          Specify a root agent ID to only manage agents under that hierarchy.
        </p>
      </div>
    </div>
  )
}
