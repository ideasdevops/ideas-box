export type Conector = { conector: string; herramientas: string[] }

export type Agente = {
  nombre: string
  dominio: string
  descripcion: string
  tools: string
  modelo: string
  conectores: Conector[]
  archivo: string
}

export type AgenteFicha = Agente & { instrucciones: string; skills: Skill[] }

export type Skill = {
  nombre: string
  dominio: string
  descripcion: string
  carpeta: string
  origen: string
  archivo: string
}

export type SkillFicha = Skill & { contenido: string; agentes: string[] }

export type Modo = 'carpeta' | 'analizar'

export type Tarea = {
  id: number
  titulo: string
  descripcion: string
  agente_sugerido: string
  server_objetivo: string
  prioridad: 'baja' | 'media' | 'alta'
  estado: 'pendiente' | 'en_progreso' | 'listo_para_revision' | 'hecho' | 'descartada'
  programada_para: string | null
  recurrencia: 'ninguna' | 'diaria' | 'semanal' | 'mensual'
  proximo_vencimiento: string | null
  auto_publicar: 0 | 1
  resultado_ejecucion: string | null
  fuente: 'manual' | 'chat'
  pr_url: string | null
  ejecucion: 'manual' | 'auto'
  modo: Modo
  ultima_ejecucion_id: number | null
  creada_en: string
  actualizada_en: string
}

export type TareaNueva = {
  titulo: string
  descripcion: string
  agente_sugerido: string
  server_objetivo: string
  prioridad: Tarea['prioridad']
  recurrencia: Tarea['recurrencia']
  auto_publicar: boolean
  programada_para: string | null
  ejecucion: Tarea['ejecucion']
  modo: Modo
}

export type TaskTemplate = { id: number; nombre: string; titulo: string; descripcion: string; agente_sugerido: string }

export type ServerEntry = { alias: string; label: string; mcps: string[]; toolgroups: string[] }

export type Profile = { empresa: string; rubro: string; sitio: string; responsable: string; claude: boolean; raiz: string }

export type Run = {
  id: number
  tipo: 'tarea' | 'chat' | 'mantenimiento'
  titulo: string
  prompt: string
  agente: string
  modo: Modo
  tarea_id: number | null
  hilo_id: number | null
  accion: string
  estado: 'en_cola' | 'corriendo' | 'ok' | 'error' | 'cancelado'
  origen: 'manual' | 'programada'
  session_id: string | null
  resultado: string | null
  bloqueos: string | null
  costo_usd: number | null
  turnos: number | null
  revisado: 0 | 1
  creada_en: string
  inicio: string | null
  fin: string | null
}

export type RunEvento = {
  n: number
  t: string
  tipo: 'sistema' | 'texto' | 'herramienta' | 'resultado' | 'bloqueo' | 'final' | 'error' | 'linea' | 'fin'
  texto: string
  herramienta?: string
  error?: boolean
  estado?: Run['estado']
  costo?: number
  turnos?: number
}

export type Hilo = {
  id: number
  agente: string
  titulo: string
  modo: Modo
  session_id: string | null
  creado_en: string
  actualizado_en: string
  mensajes?: number
  ultimo_estado?: Run['estado'] | null
}

export type HiloDetalle = Hilo & { mensajes: (Run & { eventos: RunEvento[] })[] }

export type Sugerencia = {
  tipo: 'recomendacion' | 'recordatorio'
  nivel: 'alerta' | 'accion' | 'sugerencia'
  titulo: string
  detalle: string
  clave: string
  accion:
    | { tipo: 'mantenimiento'; accion: string }
    | { tipo: 'ir'; a: string }
    | { tipo: 'ejecucion'; id: number }
    | { tipo: 'tarea'; id: number }
    | { tipo: 'recordatorio'; id: number }
    | null
}

export type Proxima = {
  tarea_id: number
  titulo: string
  agente: string
  cuando: string
  ejecucion: Tarea['ejecucion']
  modo: Modo
  recurrencia: Tarea['recurrencia']
}

export type Recordatorio = { id: number; texto: string; cuando: string | null; hecho: 0 | 1; creado_en: string }

export type Programacion = {
  corriendo: Run[]
  en_cola: Run[]
  proximas: Proxima[]
  vencidas: Tarea[]
  recientes: Run[]
  recordatorios: Recordatorio[]
  sugerencias: Sugerencia[]
  autostart: boolean
  ahora: string
}

export type Sesion = {
  id: string
  titulo: string
  carpeta: string
  actualizada: string
  activa: boolean
  origen: 'panel' | 'terminal'
  mensajes: number
}

export type SesionEntrada = {
  n: number
  hora: string
  tipo: 'pedido' | 'texto' | 'herramienta' | 'resultado'
  texto: string
  herramienta?: string
  error?: boolean
}

export type ConectorCatalogo = {
  id: string
  titulo: string
  descripcion: string
  nivel: string
  recomendado: boolean
  multi: boolean
  etiqueta: string
  login: boolean
  tipo: string
  campos: { clave: string; texto: string; secreto: boolean }[]
  instalado: string[]
}

export type Mantenimiento = {
  acciones: { id: string; titulo: string }[]
  autostart: boolean
  conectores: ConectorCatalogo[]
  packs: { id: string; nivel: string; area: string; descripcion: string }[]
}

export type Ajustes = { modelo: string; max_turnos: number }

async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`/api${path}`, { headers: { 'Content-Type': 'application/json' }, ...init })
  if (!res.ok) {
    let detalle = ''
    try {
      const body = await res.json()
      detalle = typeof body.detail === 'string' ? body.detail : JSON.stringify(body.detail ?? body)
    } catch {
      detalle = res.statusText
    }
    throw new Error(detalle || `Error ${res.status}`)
  }
  return res.json()
}

const post = <T,>(path: string, body: unknown = {}) => req<T>(path, { method: 'POST', body: JSON.stringify(body) })

export const api = {
  profile: () => req<Profile>('/profile'),
  agents: () => req<{ total: number; agentes: Agente[] }>('/agents'),
  agent: (nombre: string) => req<AgenteFicha>(`/agents/${encodeURIComponent(nombre)}`),
  skills: () => req<{ total: number; skills: Skill[] }>('/skills'),
  skill: (dominio: string, carpeta: string) => req<SkillFicha>(`/skills/${dominio}/${encodeURIComponent(carpeta)}`),
  servers: () => req<{ total: number; servers: ServerEntry[] }>('/servers'),

  tasks: () => req<{ total: number; tareas: Tarea[] }>('/tasks'),
  taskTemplates: () => req<{ templates: TaskTemplate[] }>('/tasks/templates'),
  createTask: (t: TareaNueva) => post<Tarea>('/tasks', t),
  updateTask: (id: number, patch: Partial<Tarea>) => req<Tarea>(`/tasks/${id}`, { method: 'PATCH', body: JSON.stringify(patch) }),
  deleteTask: (id: number) => req<{ ok: boolean }>(`/tasks/${id}`, { method: 'DELETE' }),
  generatePrompt: (id: number) => req<{ task_id: number; prompt: string }>(`/tasks/${id}/prompt`),
  runTask: (id: number) => post<{ run_id: number }>(`/tasks/${id}/ejecutar`),
  taskRuns: (id: number) => req<{ ejecuciones: Run[] }>(`/tasks/${id}/ejecuciones`),
  taskFromWords: (mensaje: string) => post<{ respuesta: string; tarea_creada: Tarea | null }>('/chat', { mensaje }),

  runs: (q: { estado?: string; tipo?: string; limite?: number } = {}) => {
    const p = new URLSearchParams()
    if (q.estado) p.set('estado', q.estado)
    if (q.tipo) p.set('tipo', q.tipo)
    if (q.limite) p.set('limite', String(q.limite))
    return req<{ ejecuciones: Run[] }>(`/runs?${p}`)
  },
  run: (id: number) => req<Run & { eventos: RunEvento[] }>(`/runs/${id}`),
  newRun: (b: { agente: string; pedido: string; modo: Modo }) => post<Run>('/runs', b),
  cancelRun: (id: number) => post<{ ok: boolean }>(`/runs/${id}/cancelar`),
  reviewedRun: (id: number) => post<{ ok: boolean }>(`/runs/${id}/revisado`),

  hilos: () => req<{ hilos: Hilo[] }>('/hilos'),
  hilo: (id: number) => req<HiloDetalle>(`/hilos/${id}`),
  newHilo: (agente: string, modo: Modo) => post<Hilo>('/hilos', { agente, modo }),
  sendHilo: (id: number, texto: string, modo: Modo) => post<{ run_id: number }>(`/hilos/${id}/mensaje`, { texto, modo }),
  deleteHilo: (id: number) => req<{ ok: boolean }>(`/hilos/${id}`, { method: 'DELETE' }),

  programacion: () => req<Programacion>('/programacion'),
  newRecordatorio: (texto: string, cuando: string | null) => post<Recordatorio>('/recordatorios', { texto, cuando }),
  doneRecordatorio: (id: number) => post<{ ok: boolean }>(`/recordatorios/${id}/hecho`),

  sesiones: () => req<{ sesiones: Sesion[] }>('/sesiones'),
  sesion: (id: string, desde = 0) => req<{ id: string; entradas: SesionEntrada[]; siguiente: number; activa: boolean }>(`/sesiones/${id}?desde=${desde}`),

  mantenimiento: () => req<Mantenimiento>('/mantenimiento'),
  maint: (b: { accion: string; pack?: string; conector?: string; etiqueta?: string; claves?: Record<string, string>; login?: boolean; servidor?: string }) =>
    post<{ run_id: number }>('/mantenimiento', b),
  autostart: (activo: boolean) => post<{ autostart: boolean; detalle: string }>('/mantenimiento/autostart', { activo }),
  restart: () => post<{ ok: boolean }>('/mantenimiento/reiniciar'),
  ajustes: () => req<Ajustes>('/mantenimiento/ajustes'),
  saveAjustes: (a: Partial<Ajustes>) => post<Ajustes>('/mantenimiento/ajustes', a),
}

// --- utilidades de presentación compartidas ---------------------------------------------

export const AREA: Record<string, string> = {
  core: 'Dirección', dev: 'Desarrollo', ops: 'Operaciones', qa: 'Calidad', ventas: 'Ventas',
  marketing: 'Marketing', contenido: 'Contenido', clientes: 'Clientes', internos: 'Internos',
}

export const ESTADO_RUN: Record<Run['estado'], string> = {
  en_cola: 'en la fila', corriendo: 'trabajando', ok: 'terminó', error: 'con error', cancelado: 'cancelada',
}

export function fechaLinda(iso: string | null | undefined) {
  if (!iso) return ''
  const d = new Date(iso.replace(' ', 'T'))
  if (Number.isNaN(d.getTime())) return iso
  const hoy = new Date()
  const manana = new Date(hoy.getTime() + 86400000)
  const hora = d.toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' })
  if (d.toDateString() === hoy.toDateString()) return `hoy ${hora}`
  if (d.toDateString() === manana.toDateString()) return `mañana ${hora}`
  return `${d.toLocaleDateString('es', { weekday: 'short', day: 'numeric', month: 'short' })} ${hora}`
}
