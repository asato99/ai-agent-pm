import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { readFileSync, existsSync } from 'fs'
import { homedir } from 'os'
import { join } from 'path'

// Read port from macOS app's config file (synced with Settings)
// Priority: env var > app config file > default (8080)
function getApiPort(): string {
  // 1. Environment variable
  if (process.env.AIAGENTPM_WEBSERVER_PORT) {
    return process.env.AIAGENTPM_WEBSERVER_PORT
  }

  // 2. App config file (written by macOS app when port is changed in Settings)
  const portFile = join(homedir(), 'Library/Application Support/AIAgentPM/webserver-port')
  if (existsSync(portFile)) {
    try {
      const port = readFileSync(portFile, 'utf-8').trim()
      if (port && /^\d+$/.test(port)) {
        return port
      }
    } catch {
      // ignore read errors
    }
  }

  // 3. Default
  return '8080'
}

const API_PORT = getApiPort()
console.log(`[vite] REST API server port: ${API_PORT}`)

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': '/src',
    },
  },
  // Inject API port as environment variable for client-side use
  define: {
    'import.meta.env.VITE_API_PORT': JSON.stringify(API_PORT),
  },
  server: {
    port: 5173,
    // No proxy needed - client accesses REST server directly via CORS
  },
})
