import { create } from 'zustand'

type ConnectionStatus = 'connected' | 'disconnected' | 'reconnecting'

interface ConnectionStore {
  status: ConnectionStatus
  lastSync: Date | null
  setStatus: (status: ConnectionStatus) => void
  setLastSync: (date: Date) => void
}

export const useConnectionStore = create<ConnectionStore>((set) => ({
  status: 'disconnected',
  lastSync: null,

  setStatus: (status) => set({ status }),
  setLastSync: (date) => set({ lastSync: date }),
}))
