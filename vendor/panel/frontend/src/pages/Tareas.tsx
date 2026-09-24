import { useEffect, useState } from 'react'
import { api, type Tarea, type TaskTemplate } from '../api'
import { Badge, Button, EmptyState, Modal, Panel, SectionHeader } from '../components/ui'

// Unicos agentes elegibles para ejecucion autonoma -- mismo set que
// backend/routers/execution.py#AGENTES_ELEGIBLES, mantener sincronizado.
const AGENTES_ELEGIBLES = new Set(['content-strategist', 'design-content'])

const ESTADO_TONE: Record<Tarea['estado'], 'default' | 'accent' | 'ok' | 'warn'> = {
  pendiente: 'default',
  en_progreso: 'warn',
  listo_para_revision: 'accent',
  hecho: 'ok',
  descartada: 'default',
}

const PRIORIDAD_TONE: Record<Tarea['prioridad'], 'default' | 'warn' | 'danger'> = {
  baja: 'default',
  media: 'warn',
  alta: 'danger',
}

const RECURRENCIA_LABEL: Record<Tarea['recurrencia'], string> = {
  ninguna: 'única vez',
  diaria: 'diaria',
  semanal: 'semanal',
  mensual: 'mensual',
}

function emptyDraft() {
  return {
    titulo: '',
    descripcion: '',
    agente_sugerido: '',
    server_objetivo: '',
    prioridad: 'media' as const,
    recurrencia: 'ninguna' as Tarea['recurrencia'],
    auto_publicar: false,
  }
}

export default function TareasPage() {
  const [tareas, setTareas] = useState<Tarea[] | null>(null)
  const [templates, setTemplates] = useState<TaskTemplate[]>([])
  const [draft, setDraft] = useState(emptyDraft())
  const [showForm, setShowForm] = useState(false)
  const [promptFor, setPromptFor] = useState<{ titulo: string; texto: string } | null>(null)
  const [copied, setCopied] = useState(false)
  const [resultadoFor, setResultadoFor] = useState<{ titulo: string; texto: string; alertaOk: boolean } | null>(null)
  const [ejecutando, setEjecutando] = useState<number | null>(null)

  const refresh = () => api.tasks().then((r) => setTareas(r.tareas))

  useEffect(() => {
    refresh()
    api.taskTemplates().then((r) => setTemplates(r.templates))
  }, [])

  const applyTemplate = (t: TaskTemplate) => {
    // Deteccion simple por nombre -- si el template es de backup/recurrente por
    // naturaleza, prellenar la recurrencia sugerida en vez de dejarla en "ninguna".
    const recurrencia: Tarea['recurrencia'] = /mensual/i.test(t.nombre) ? 'mensual' : 'ninguna'
    setDraft({ ...emptyDraft(), titulo: t.titulo, descripcion: t.descripcion, agente_sugerido: t.agente_sugerido, recurrencia })
    setShowForm(true)
  }

  const submit = async () => {
    if (!draft.titulo.trim()) return
    await api.createTask(draft)
    setDraft(emptyDraft())
    setShowForm(false)
    refresh()
  }

  const setEstado = async (id: number, estado: Tarea['estado']) => {
    await api.updateTask(id, { estado })
    refresh()
    if (estado === 'en_progreso') {
      openPrompt(id)
    }
  }

  const remove = async (id: number) => {
    await api.deleteTask(id)
    refresh()
  }

  const openPrompt = async (id: number, titulo?: string) => {
    setCopied(false)
    const t = titulo ?? tareas?.find((x) => x.id === id)?.titulo ?? ''
    const { prompt } = await api.generatePrompt(id)
    setPromptFor({ titulo: t, texto: prompt })
  }

  const copyPrompt = async () => {
    if (!promptFor) return
    await navigator.clipboard.writeText(promptFor.texto)
    setCopied(true)
  }

  const ejecutar = async (t: Tarea) => {
    setEjecutando(t.id)
    try {
      const { tarea, aviso } = await api.ejecutarTarea(t.id)
      refresh()
      setResultadoFor({ titulo: tarea.titulo, texto: tarea.resultado_ejecucion ?? '', alertaOk: aviso.ok })
    } catch (e) {
      alert(`Error ejecutando la tarea: ${e}`)
      refresh()
    } finally {
      setEjecutando(null)
    }
  }

  return (
    <div>
      <SectionHeader
        title="Tablero de tareas"
        subtitle="Registra el trabajo pendiente y contexto listo para ejecutar — no dispara nada por su cuenta"
        action={<Button onClick={() => setShowForm((s) => !s)}>{showForm ? 'Cerrar' : '+ Nueva tarea'}</Button>}
      />

      {showForm && (
        <Panel className="p-4 mb-6">
          <div className="text-xs uppercase tracking-wider text-muted mb-3">Plantillas frecuentes</div>
          <div className="flex flex-wrap gap-2 mb-4">
            {templates.map((t) => (
              <button
                key={t.id}
                onClick={() => applyTemplate(t)}
                className="text-xs px-2.5 py-1 border border-border text-muted hover:text-accent hover:border-accent transition-colors"
              >
                {t.nombre}
              </button>
            ))}
          </div>
          <div className="grid grid-cols-2 gap-3">
            <input
              className="col-span-2 bg-panel-raised border border-border px-3 py-2 text-sm text-white placeholder:text-muted focus:outline-none focus:border-accent"
              placeholder="Título"
              value={draft.titulo}
              onChange={(e) => setDraft({ ...draft, titulo: e.target.value })}
            />
            <textarea
              className="col-span-2 bg-panel-raised border border-border px-3 py-2 text-sm text-white placeholder:text-muted focus:outline-none focus:border-accent"
              placeholder="Descripción / contexto"
              rows={3}
              value={draft.descripcion}
              onChange={(e) => setDraft({ ...draft, descripcion: e.target.value })}
            />
            <input
              className="bg-panel-raised border border-border px-3 py-2 text-sm text-white placeholder:text-muted focus:outline-none focus:border-accent"
              placeholder="Agente sugerido (ej. dev-saas)"
              value={draft.agente_sugerido}
              onChange={(e) => setDraft({ ...draft, agente_sugerido: e.target.value })}
            />
            <input
              className="bg-panel-raised border border-border px-3 py-2 text-sm text-white placeholder:text-muted focus:outline-none focus:border-accent"
              placeholder="Server objetivo (opcional)"
              value={draft.server_objetivo}
              onChange={(e) => setDraft({ ...draft, server_objetivo: e.target.value })}
            />
            <select
              className="col-span-2 bg-panel-raised border border-border px-3 py-2 text-sm text-white focus:outline-none focus:border-accent"
              value={draft.recurrencia}
              onChange={(e) => setDraft({ ...draft, recurrencia: e.target.value as Tarea['recurrencia'] })}
            >
              <option value="ninguna">Única vez</option>
              <option value="diaria">Se repite diariamente</option>
              <option value="semanal">Se repite semanalmente</option>
              <option value="mensual">Se repite mensualmente (ej. backups de VPS)</option>
            </select>
            <label className="col-span-2 flex items-center gap-2 text-xs text-muted">
              <input
                type="checkbox"
                checked={draft.auto_publicar}
                onChange={(e) => setDraft({ ...draft, auto_publicar: e.target.checked })}
              />
              Publicar automáticamente al terminar (solo tareas de contenido — la publicación
              real la hace una persona, esto solo cambia el texto del aviso)
            </label>
          </div>
          <div className="mt-3 flex justify-end">
            <Button onClick={submit}>Crear tarea</Button>
          </div>
        </Panel>
      )}

      {!tareas && <EmptyState label="Cargando..." />}
      {tareas && tareas.length === 0 && <EmptyState label="Sin tareas todavía" />}
      <div className="space-y-2">
        {tareas?.map((t) => (
          <Panel key={t.id} className="p-4">
            <div className="flex items-start justify-between gap-4">
              <div className="min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-sm font-medium text-white">{t.titulo}</span>
                  <Badge tone={PRIORIDAD_TONE[t.prioridad]}>{t.prioridad}</Badge>
                  <Badge tone={ESTADO_TONE[t.estado]}>{t.estado.replace('_', ' ')}</Badge>
                  {t.fuente === 'chat' && <Badge tone="accent">creada por chat</Badge>}
                  {t.recurrencia !== 'ninguna' && <Badge>↻ {RECURRENCIA_LABEL[t.recurrencia]}</Badge>}
                  {t.auto_publicar === 1 && <Badge tone="warn">auto-publicar</Badge>}
                </div>
                {t.descripcion && <p className="text-xs text-muted mb-1">{t.descripcion}</p>}
                <div className="flex gap-3 text-[11px] text-muted">
                  {t.agente_sugerido && <span>agente: {t.agente_sugerido}</span>}
                  {t.server_objetivo && <span>server: {t.server_objetivo}</span>}
                  {t.proximo_vencimiento && <span>próximo: {t.proximo_vencimiento}</span>}
                  {t.pr_url && (
                    <a href={t.pr_url} target="_blank" rel="noreferrer" className="text-accent hover:underline">
                      ver PR
                    </a>
                  )}
                  {t.estado === 'listo_para_revision' && (
                    <button
                      onClick={() => setResultadoFor({ titulo: t.titulo, texto: t.resultado_ejecucion ?? '', alertaOk: true })}
                      className="text-accent hover:underline"
                    >
                      ver resultado
                    </button>
                  )}
                </div>
              </div>
              <div className="flex gap-1.5 shrink-0">
                <Button variant="ghost" onClick={() => openPrompt(t.id, t.titulo)}>Prompt</Button>
                {AGENTES_ELEGIBLES.has(t.agente_sugerido) && t.estado === 'pendiente' && (
                  <Button variant="ghost" onClick={() => ejecutar(t)}>
                    {ejecutando === t.id ? 'Ejecutando...' : 'Ejecutar'}
                  </Button>
                )}
                {t.estado !== 'en_progreso' && t.estado !== 'hecho' && t.estado !== 'listo_para_revision' && (
                  <Button variant="ghost" onClick={() => setEstado(t.id, 'en_progreso')}>En progreso</Button>
                )}
                {t.estado !== 'hecho' && (
                  <Button variant="ghost" onClick={() => setEstado(t.id, 'hecho')}>
                    {t.recurrencia !== 'ninguna' ? 'Completar y reprogramar' : 'Hecho'}
                  </Button>
                )}
                <Button variant="danger" onClick={() => remove(t.id)}>Borrar</Button>
              </div>
            </div>
          </Panel>
        ))}
      </div>

      {promptFor && (
        <Modal title={`Prompt — ${promptFor.titulo}`} onClose={() => setPromptFor(null)}>
          <pre className="text-xs text-muted whitespace-pre-wrap leading-relaxed bg-panel-raised border border-border p-3 max-h-96 overflow-y-auto">
            {promptFor.texto}
          </pre>
          <div className="mt-3 flex justify-end">
            <Button onClick={copyPrompt}>{copied ? 'Copiado' : 'Copiar al portapapeles'}</Button>
          </div>
        </Modal>
      )}

      {resultadoFor && (
        <Modal title={`Resultado — ${resultadoFor.titulo}`} onClose={() => setResultadoFor(null)}>
          <div className="text-xs text-muted mb-2">
            {resultadoFor.alertaOk
              ? 'Aviso enviado.'
              : 'No se envió el aviso (sin canal configurado o con error) — el contenido igual quedó guardado acá.'}
          </div>
          <pre className="text-xs text-white whitespace-pre-wrap leading-relaxed bg-panel-raised border border-border p-3 max-h-96 overflow-y-auto">
            {resultadoFor.texto}
          </pre>
        </Modal>
      )}
    </div>
  )
}
