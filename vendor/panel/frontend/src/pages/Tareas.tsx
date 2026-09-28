import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { api, fechaLinda, type Agente, type Run, type Tarea, type TareaNueva, type TaskTemplate } from '../api'
import { AgentSelect, ModoSelector, RunBadge, RunView } from '../components/run'
import { Badge, Button, Chips, EmptyState, Field, Input, Modal, Panel, SectionHeader, Select, Tabs, TextArea } from '../components/ui'
import { Markdown } from '../components/markdown'
import { localAhoraMas } from './Programacion'

const ESTADO: Record<Tarea['estado'], { label: string; tone: 'default' | 'accent' | 'ok' | 'warn' }> = {
  pendiente: { label: 'pendiente', tone: 'default' },
  en_progreso: { label: 'en curso', tone: 'warn' },
  listo_para_revision: { label: 'para revisar', tone: 'accent' },
  hecho: { label: 'hecha', tone: 'ok' },
  descartada: { label: 'descartada', tone: 'default' },
}
const REPETIR: Record<Tarea['recurrencia'], string> = { ninguna: 'Una sola vez', diaria: 'Todos los días', semanal: 'Todas las semanas', mensual: 'Todos los meses' }

function vacia(agente = ''): TareaNueva {
  return {
    titulo: '', descripcion: '', agente_sugerido: agente, server_objetivo: '', prioridad: 'media',
    recurrencia: 'ninguna', auto_publicar: false, programada_para: null, ejecucion: 'manual', modo: 'carpeta',
  }
}

function Formulario({ inicial, agentes, templates, onGuardar, onCancelar, editando }: {
  inicial: TareaNueva; agentes: Agente[]; templates: TaskTemplate[]; onGuardar: (t: TareaNueva) => Promise<void>; onCancelar: () => void; editando: boolean
}) {
  const [t, setT] = useState<TareaNueva>(inicial)
  const [guardando, setGuardando] = useState(false)
  const set = <K extends keyof TareaNueva>(k: K, v: TareaNueva[K]) => setT((x) => ({ ...x, [k]: v }))
  const programar = Boolean(t.programada_para)
  return (
    <div className="space-y-4">
      {!editando && templates.length > 0 && (
        <div>
          <div className="text-xs text-muted mb-2">Empezar desde una plantilla</div>
          <div className="flex flex-wrap gap-1.5">
            {templates.map((p) => (
              <button key={p.id} onClick={() => setT({ ...t, titulo: p.titulo, descripcion: p.descripcion, agente_sugerido: p.agente_sugerido, recurrencia: /backup/i.test(p.nombre) ? 'mensual' : t.recurrencia })}
                className="text-xs px-2.5 py-1 border border-border text-muted hover:text-accent hover:border-accent">{p.nombre}</button>
            ))}
          </div>
        </div>
      )}
      <Field label="Qué hay que hacer"><Input value={t.titulo} onChange={(e) => set('titulo', e.target.value)} placeholder="Ej: Resumen semanal de pendientes con clientes" autoFocus /></Field>
      <Field label="Detalle y contexto" hint="Cuanto más claro, mejor trabaja el agente: qué entregar, dónde dejarlo, qué evitar.">
        <TextArea rows={4} value={t.descripcion} onChange={(e) => set('descripcion', e.target.value)} />
      </Field>
      <div className="grid grid-cols-2 gap-4">
        <Field label="Agente"><AgentSelect value={t.agente_sugerido} onChange={(v) => set('agente_sugerido', v)} agentes={agentes} allowEmpty /></Field>
        <Field label="Prioridad">
          <Select value={t.prioridad} onChange={(e) => set('prioridad', e.target.value as Tarea['prioridad'])}>
            <option value="baja">Baja</option><option value="media">Media</option><option value="alta">Alta</option>
          </Select>
        </Field>
      </div>
      <Field label="Qué puede hacer el agente"><ModoSelector value={t.modo} onChange={(v) => set('modo', v)} /></Field>
      <div className="border border-border p-3 space-y-3">
        <label className="flex items-center gap-2 text-sm text-white">
          <input type="checkbox" checked={programar} onChange={(e) => set('programada_para', e.target.checked ? localAhoraMas(1) : null)} />
          Programarla para una fecha y hora
        </label>
        {programar && (
          <div className="grid grid-cols-2 gap-4">
            <Field label="Cuándo"><Input type="datetime-local" value={t.programada_para ?? ''} onChange={(e) => set('programada_para', e.target.value || null)} /></Field>
            <Field label="Se repite">
              <Select value={t.recurrencia} onChange={(e) => set('recurrencia', e.target.value as Tarea['recurrencia'])}>
                {Object.entries(REPETIR).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
              </Select>
            </Field>
            <div className="col-span-2">
              <Chips value={t.ejecucion} onChange={(v) => set('ejecucion', v)} options={[
                { value: 'auto', label: 'Que se ejecute sola a esa hora' },
                { value: 'manual', label: 'Solo recordármela' },
              ]} />
              <div className="text-[11px] text-muted mt-1.5">
                {t.ejecucion === 'auto'
                  ? 'A la hora, el agente la trabaja solo y el resultado queda para que lo revises. Necesita el panel abierto (o el arranque automático).'
                  : 'A la hora te aparece como recordatorio en «Hoy»; la lanzás vos con un clic.'}
              </div>
            </div>
          </div>
        )}
      </div>
      <div className="flex justify-end gap-2">
        <Button variant="ghost" onClick={onCancelar}>Cancelar</Button>
        <Button disabled={!t.titulo.trim() || guardando} onClick={async () => { setGuardando(true); try { await onGuardar(t) } finally { setGuardando(false) } }}>
          {editando ? 'Guardar cambios' : 'Crear tarea'}
        </Button>
      </div>
    </div>
  )
}

function ConPalabras({ onCreada }: { onCreada: () => void }) {
  const [texto, setTexto] = useState('')
  const [respuesta, setRespuesta] = useState('')
  const [pensando, setPensando] = useState(false)
  const enviar = async () => {
    setPensando(true)
    setRespuesta('')
    try {
      const r = await api.taskFromWords(texto)
      setRespuesta(r.respuesta + (r.tarea_creada ? `\n\n✓ Tarea creada: «${r.tarea_creada.titulo}»` : ''))
      if (r.tarea_creada) { setTexto(''); onCreada() }
    } catch (e) {
      setRespuesta(`No pude: ${(e as Error).message}`)
    } finally {
      setPensando(false)
    }
  }
  return (
    <div className="space-y-3">
      <TextArea rows={3} value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Ej: todos los lunes a las 9 quiero un resumen de los clientes con pagos pendientes" />
      <div className="flex justify-end"><Button onClick={enviar} disabled={pensando || !texto.trim()}>{pensando ? 'Pensando…' : 'Armar la tarea'}</Button></div>
      {respuesta && <div className="border border-border bg-panel-raised p-3"><Markdown text={respuesta} /></div>}
      <div className="text-[11px] text-muted">Si falta algún dato, te lo pregunta antes de crearla. Para agendarla, después editala y poné fecha y hora.</div>
    </div>
  )
}

export default function TareasPage() {
  const [params, setParams] = useSearchParams()
  const [tareas, setTareas] = useState<Tarea[] | null>(null)
  const [agentes, setAgentes] = useState<Agente[]>([])
  const [templates, setTemplates] = useState<TaskTemplate[]>([])
  const [filtro, setFiltro] = useState<'activas' | 'revisar' | 'programadas' | 'hechas'>('activas')
  const [form, setForm] = useState<{ modo: 'nueva' | 'palabras' } | { editar: Tarea } | null>(params.get('nueva') ? { modo: 'nueva' } : null)
  const [runVisible, setRunVisible] = useState<number | null>(null)
  const [historial, setHistorial] = useState<{ tarea: Tarea; runs: Run[] } | null>(null)
  const [prompt, setPrompt] = useState<{ titulo: string; texto: string } | null>(null)

  const cargar = () => api.tasks().then((r) => setTareas(r.tareas))
  useEffect(() => {
    cargar()
    api.agents().then((r) => setAgentes(r.agentes))
    api.taskTemplates().then((r) => setTemplates(r.templates))
    const t = setInterval(cargar, 8000)
    return () => clearInterval(t)
  }, [])
  useEffect(() => {
    const ver = Number(params.get('ver'))
    if (ver && tareas) {
      const t = tareas.find((x) => x.id === ver)
      if (t) abrirHistorial(t)
      setParams({})
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tareas])

  const abrirHistorial = async (t: Tarea) => setHistorial({ tarea: t, runs: (await api.taskRuns(t.id)).ejecuciones })
  const ejecutar = async (t: Tarea) => {
    try {
      const { run_id } = await api.runTask(t.id)
      setRunVisible(run_id)
      cargar()
    } catch (e) {
      alert((e as Error).message)
    }
  }
  const hecho = async (t: Tarea) => { await api.updateTask(t.id, { estado: 'hecho' }); cargar() }

  const lista = (tareas ?? []).filter((t) =>
    filtro === 'activas' ? !['hecho', 'descartada'].includes(t.estado) :
    filtro === 'revisar' ? t.estado === 'listo_para_revision' :
    filtro === 'programadas' ? Boolean(t.programada_para) && !['hecho', 'descartada'].includes(t.estado) :
    ['hecho', 'descartada'].includes(t.estado))

  return (
    <div>
      <SectionHeader
        title="Tareas"
        subtitle="El trabajo de tu equipo de agentes: lanzalas cuando quieras, o programalas para que se hagan solas."
        action={<>
          <Button variant="ghost" onClick={() => setForm({ modo: 'palabras' })}>Con mis palabras</Button>
          <Button onClick={() => setForm({ modo: 'nueva' })}>+ Nueva tarea</Button>
        </>}
      />
      <Tabs value={filtro} onChange={setFiltro} options={[
        { value: 'activas', label: 'Activas' },
        { value: 'revisar', label: `Para revisar${tareas ? ` (${tareas.filter((t) => t.estado === 'listo_para_revision').length})` : ''}` },
        { value: 'programadas', label: 'Programadas' },
        { value: 'hechas', label: 'Hechas' },
      ]} />
      {!tareas && <EmptyState label="Cargando…" />}
      {tareas && lista.length === 0 && <EmptyState label="No hay tareas acá." />}
      <div className="space-y-2">
        {lista.map((t) => (
          <Panel key={t.id} className="p-4">
            <div className="flex items-start justify-between gap-4">
              <div className="min-w-0">
                <div className="flex items-center gap-2 flex-wrap mb-1">
                  <span className="text-sm font-medium text-white">{t.titulo}</span>
                  <Badge tone={ESTADO[t.estado].tone}>{ESTADO[t.estado].label}</Badge>
                  {t.prioridad === 'alta' && <Badge tone="danger">prioridad alta</Badge>}
                  {t.programada_para && <Badge tone={t.ejecucion === 'auto' ? 'accent' : 'default'}>{t.ejecucion === 'auto' ? '⏱ se ejecuta sola' : '⏰ recordatorio'} · {fechaLinda(t.programada_para)}</Badge>}
                  {t.recurrencia !== 'ninguna' && <Badge>↻ {REPETIR[t.recurrencia].toLowerCase()}</Badge>}
                  <Badge>{t.modo === 'carpeta' ? 'puede trabajar' : 'solo analiza'}</Badge>
                </div>
                {t.descripcion && <p className="text-xs text-muted mb-1 line-clamp-2">{t.descripcion}</p>}
                <div className="text-[11px] text-muted">{t.agente_sugerido ? `agente: ${t.agente_sugerido}` : 'sin agente asignado'}</div>
              </div>
              <div className="flex gap-1.5 shrink-0 flex-wrap justify-end">
                {!['hecho', 'descartada'].includes(t.estado) && <Button small onClick={() => ejecutar(t)}>Ejecutar ahora</Button>}
                {t.ultima_ejecucion_id && <Button small variant="ghost" onClick={() => setRunVisible(t.ultima_ejecucion_id)}>Último resultado</Button>}
                <Button small variant="ghost" onClick={() => abrirHistorial(t)}>Historial</Button>
                <Button small variant="ghost" onClick={() => setForm({ editar: t })}>Editar</Button>
                {t.estado !== 'hecho' && <Button small variant="ghost" onClick={() => hecho(t)}>{t.recurrencia !== 'ninguna' ? 'Hecha, a la próxima' : 'Hecha'}</Button>}
                <Button small variant="quiet" title="Copiar el pedido para usarlo en la terminal" onClick={async () => setPrompt({ titulo: t.titulo, texto: (await api.generatePrompt(t.id)).prompt })}>Prompt</Button>
                <Button small variant="quiet" onClick={() => confirm(`¿Borrar «${t.titulo}»?`) && api.deleteTask(t.id).then(cargar)}>Borrar</Button>
              </div>
            </div>
          </Panel>
        ))}
      </div>

      {form && (
        <Modal title={'editar' in form ? 'Editar tarea' : form.modo === 'palabras' ? 'Nueva tarea con tus palabras' : 'Nueva tarea'} onClose={() => setForm(null)}>
          {'editar' in form ? (
            <Formulario editando agentes={agentes} templates={templates} onCancelar={() => setForm(null)}
              inicial={{ ...form.editar, auto_publicar: Boolean(form.editar.auto_publicar) }}
              onGuardar={async (t) => { await api.updateTask(form.editar.id, { ...t, auto_publicar: t.auto_publicar ? 1 : 0 }); setForm(null); cargar() }} />
          ) : form.modo === 'palabras' ? (
            <ConPalabras onCreada={cargar} />
          ) : (
            <Formulario editando={false} agentes={agentes} templates={templates} onCancelar={() => setForm(null)}
              inicial={vacia(params.get('agente') ?? '')}
              onGuardar={async (t) => { await api.createTask(t); setForm(null); setParams({}); cargar() }} />
          )}
        </Modal>
      )}
      {runVisible && <Modal title="Ejecución" wide onClose={() => { setRunVisible(null); cargar() }}><RunView runId={runVisible} onChanged={cargar} /></Modal>}
      {historial && (
        <Modal title={`Historial — ${historial.tarea.titulo}`} onClose={() => setHistorial(null)}>
          {historial.runs.length === 0 && <EmptyState label="Todavía no se ejecutó." />}
          <div className="space-y-1">
            {historial.runs.map((r) => (
              <button key={r.id} onClick={() => { setHistorial(null); setRunVisible(r.id) }} className="w-full text-left flex items-center gap-3 px-3 py-2 border border-border hover:border-accent/40">
                <RunBadge estado={r.estado} />
                <span className="text-xs text-muted">{fechaLinda(r.inicio ?? r.creada_en)}</span>
                <span className="text-xs text-muted">{r.origen === 'programada' ? 'programada' : 'a mano'}</span>
                <span className="flex-1" />
                {!r.revisado && r.estado !== 'en_cola' && r.estado !== 'corriendo' && <Badge tone="accent">sin revisar</Badge>}
              </button>
            ))}
          </div>
        </Modal>
      )}
      {prompt && (
        <Modal title={`Prompt — ${prompt.titulo}`} onClose={() => setPrompt(null)}>
          <p className="text-xs text-muted mb-2">Para trabajar esta tarea en una sesión de Claude en la terminal (con aprobación paso a paso).</p>
          <pre className="text-xs text-white/85 whitespace-pre-wrap bg-panel-raised border border-border p-3 max-h-96 overflow-y-auto">{prompt.texto}</pre>
          <div className="mt-3 flex justify-end"><Button onClick={() => navigator.clipboard.writeText(prompt.texto)}>Copiar</Button></div>
        </Modal>
      )}
    </div>
  )
}
