export type Agente = {
  nombre: string
  dominio: string
  descripcion: string
  tools: string
  archivo: string
}

export type Skill = {
  nombre: string
  dominio: string
  descripcion: string
  carpeta: string
  archivo: string
}

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
  creada_en: string
  actualizada_en: string
}

// Lo que se manda al crear no es una Tarea recortada: el backend recibe
// auto_publicar como booleano y devuelve 0/1, porque SQLite no tiene booleanos.
export type TareaNueva = {
  titulo: string
  descripcion: string
  agente_sugerido: string
  server_objetivo: string
  prioridad: Tarea['prioridad']
  recurrencia: Tarea['recurrencia']
  auto_publicar: boolean
}

export type TaskTemplate = {
  id: number
  nombre: string
  titulo: string
  descripcion: string
  agente_sugerido: string
}

export type ServerEntry = {
  alias: string
  label: string
  mcps: string[]
  toolgroups: string[]
}

export type Profile = {
  empresa: string
  rubro: string
  sitio: string
}

async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`/api${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  })
  if (!res.ok) {
    const body = await res.text().catch(() => '')
    throw new Error(`${res.status} ${res.statusText}: ${body}`)
  }
  return res.json()
}

export const api = {
  agents: () => req<{ total: number; agentes: Agente[] }>('/agents'),
  skills: (q?: string) => req<{ total: number; skills: Skill[] }>(`/skills${q ? `?q=${encodeURIComponent(q)}` : ''}`),
  servers: () => req<{ total: number; servers: ServerEntry[] }>('/servers'),
  tasks: (estado?: string) => req<{ total: number; tareas: Tarea[] }>(`/tasks${estado ? `?estado=${estado}` : ''}`),
  taskTemplates: () => req<{ templates: TaskTemplate[] }>('/tasks/templates'),
  createTask: (payload: TareaNueva) => req<Tarea>('/tasks', { method: 'POST', body: JSON.stringify(payload) }),
  updateTask: (id: number, patch: Partial<Tarea>) => req<Tarea>(`/tasks/${id}`, { method: 'PATCH', body: JSON.stringify(patch) }),
  deleteTask: (id: number) => req<{ ok: boolean }>(`/tasks/${id}`, { method: 'DELETE' }),
  generatePrompt: (id: number) => req<{ task_id: number; prompt: string }>(`/tasks/${id}/prompt`),
  ejecutarTarea: (id: number) => req<{ tarea: Tarea; aviso: { ok: boolean } }>(`/tasks/${id}/ejecutar`, { method: 'POST' }),
  profile: () => req<Profile>('/profile'),
  chatHistory: () => req<{ mensajes: ChatMessageRow[] }>('/chat/history'),
  sendChatMessage: (mensaje: string) =>
    req<{ respuesta: string; tarea_creada: Tarea | null }>('/chat', { method: 'POST', body: JSON.stringify({ mensaje }) }),
}

export type ChatMessageRow = {
  id: number
  rol: 'usuario' | 'asistente'
  texto: string
  tarea_creada_id: number | null
  tarea_titulo?: string | null
  tarea_agente?: string | null
  creado_en: string
}
