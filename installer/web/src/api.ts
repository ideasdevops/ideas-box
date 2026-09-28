// API local del asistente (installer/server.py). El token llega en la URL que abre la
// terminal (?t=…) y se guarda para la sesión: sin él, el servidor no responde.

const params = new URLSearchParams(window.location.search)
const fromUrl = params.get('t')
if (fromUrl) {
  sessionStorage.setItem('ib-token', fromUrl)
  // Se saca de la barra de direcciones para que no quede a la vista ni en el historial
  window.history.replaceState(null, '', window.location.pathname)
}
export const token = sessionStorage.getItem('ib-token') || ''

export type Field = { key: string; prompt: string; secret: boolean }
export type Mcp = {
  id: string
  title: string
  desc: string
  tier: 'core' | 'negocio' | 'opcional' | string
  recommended: boolean
  kind: string
  multi: boolean
  instancePrompt: string
  fields: Field[]
  login: boolean
  suggest: string
  notes: string
  requiresHost: string
  installed: boolean
}
export type Pack = { id: string; tier: string; domain: string; desc: string }
export type Info = {
  os: 'mac' | 'linux' | 'wsl'
  osPretty: string
  arch: string
  user: string
  home: string
  timezone: string
  version: string
  profile: Record<string, string>
  resume: { id: string; label: string }[]
  panelInstalled: boolean
  steps: { id: string; label: string }[]
  skipDeps: boolean
  dryRun: boolean
  status: 'idle' | 'running' | 'done' | 'failed'
  mcps: Mcp[]
  packs: Pack[]
}
export type DataRoot = { path: string; label: string; free: string; recommended: boolean; exists: boolean }

export type IbEvent =
  | { seq: number; kind: 'log'; text: string }
  | { seq: number; kind: 'step'; id: string; state: 'start' | 'done'; label: string }
  | { seq: number; kind: 'title'; text: string }
  | { seq: number; kind: 'ask'; type: 'confirm' | 'text' | 'secret'; default: string; question: string }
  | { seq: number; kind: 'answered'; seq_ask: number; text: string }
  | { seq: number; kind: 'failed'; step: string; label: string }
  | { seq: number; kind: 'summary'; empresa: string; dataRoot: string }
  | { seq: number; kind: 'exit'; code: number }
  | { seq: number; kind: 'started' }

async function call<T>(method: 'GET' | 'POST', path: string, body?: unknown): Promise<T> {
  const res = await fetch(path, {
    method,
    headers: { 'X-IB-Token': token, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error((data as { error?: string }).error || `Error ${res.status}`)
  return data as T
}

export const api = {
  info: () => call<Info>('GET', '/api/info'),
  dataroots: (slug: string) => call<{ options: DataRoot[] }>('GET', `/api/dataroots?slug=${encodeURIComponent(slug)}`),
  start: (answers: unknown) => call('POST', '/api/start', answers),
  answer: (value: string) => call('POST', '/api/answer', { value }),
  retry: () => call('POST', '/api/retry', {}),
  cancel: () => call('POST', '/api/cancel', {}),
  open: (what: 'panel' | 'folder') => call('POST', '/api/open', { what }),
  shutdown: () => call('POST', '/api/shutdown', {}),
  events: (since: number, onEvent: (e: IbEvent) => void) => {
    const es = new EventSource(`/api/events?since=${since}&t=${encodeURIComponent(token)}`)
    es.onmessage = (m) => onEvent(JSON.parse(m.data))
    return es
  },
}

// Igual que slugify() de lib/common.sh: minúsculas, sin acentos ni ñ, guiones
export function slugify(s: string) {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}
