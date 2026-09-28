import { useEffect, useMemo, useRef, useState } from 'react'
import { api } from './api'
import type { IbEvent, Info } from './api'
import { Badge, Button, Callout, Modal, Panel, SectionHeader, Spinner } from './ui'

type Ask = Extract<IbEvent, { kind: 'ask' }>
type StepState = 'pending' | 'running' | 'done' | 'failed'

// La salida del instalador tiene líneas «✓ …», «→ …», «! …», «✗ …»: se muestran con su tono
function lineTone(t: string) {
  if (t.startsWith('✓')) return 'text-emerald-400'
  if (t.startsWith('✗')) return 'text-rose-400'
  if (t.startsWith('!')) return 'text-amber-300'
  if (t.startsWith('→')) return 'text-white'
  return 'text-muted'
}

export default function Progress({ info, answers, onEdit }: { info: Info; answers: { extras: { panel: boolean } }; onEdit: () => void }) {
  const [events, setEvents] = useState<IbEvent[]>([])
  const [showLog, setShowLog] = useState(false)
  const [closed, setClosed] = useState(false)
  const logRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    let last = 0
    let es: EventSource | null = null
    const connect = () => {
      es = api.events(last, (e) => {
        last = Math.max(last, e.seq)
        setEvents((prev) => (prev.length && prev[prev.length - 1].seq >= e.seq ? prev : [...prev, e]))
      })
      // Si se corta (el equipo se suspendió, se reinició el servidor), reconecta desde el último
      es.onerror = () => {
        es?.close()
        setTimeout(connect, 2000)
      }
    }
    connect()
    return () => es?.close()
  }, [])

  // La corrida vigente es la que empezó en el último «started» (un reintento arranca otra)
  const run = useMemo(() => {
    let from = 0
    events.forEach((e, i) => { if (e.kind === 'started') from = i })
    return events.slice(from)
  }, [events])

  const steps = useMemo(() => {
    const st: Record<string, StepState> = Object.fromEntries(info.steps.map((s) => [s.id, 'pending' as StepState]))
    let current = ''
    for (const e of run) {
      if (e.kind === 'step') {
        st[e.id] = e.state === 'start' ? 'running' : 'done'
        current = e.state === 'start' ? e.id : current
      }
      if (e.kind === 'failed' && e.step) st[e.step] = 'failed'
    }
    // En una reanudación, lo que ya estaba hecho también figura como hecho
    return { st, current }
  }, [run, info.steps])

  const logs = run.filter((e): e is Extract<IbEvent, { kind: 'log' }> => e.kind === 'log' && e.text.trim() !== '')
  const exit = [...run].reverse().find((e) => e.kind === 'exit') as Extract<IbEvent, { kind: 'exit' }> | undefined
  const summary = run.find((e) => e.kind === 'summary') as Extract<IbEvent, { kind: 'summary' }> | undefined
  const answered = new Set(run.filter((e) => e.kind === 'answered').map((e) => (e as Extract<IbEvent, { kind: 'answered' }>).seq_ask))
  const pending = !exit ? (run.filter((e) => e.kind === 'ask' && !answered.has(e.seq)).pop() as Ask | undefined) : undefined
  const lastAction = [...logs].reverse().find((l) => l.text.startsWith('→') || l.text.startsWith('✓'))?.text.replace(/^[→✓]\s*/, '')
  const doneCount = Object.values(steps.st).filter((s) => s === 'done').length
  const total = info.steps.length - (info.skipDeps ? 1 : 0)

  useEffect(() => {
    if (showLog && logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight
  }, [logs.length, showLog])

  if (closed) {
    return (
      <Panel className="p-8 text-center">
        <div className="text-white">Listo, podés cerrar esta pestaña.</div>
        <div className="text-[13px] text-muted mt-1">Ideas Box te espera en el Escritorio.</div>
      </Panel>
    )
  }

  if (exit && exit.code === 0) {
    return <Done info={info} summary={summary} panel={answers.extras.panel || info.panelInstalled} onClose={async () => { await api.shutdown().catch(() => {}); setClosed(true) }} />
  }

  const failed = exit && exit.code !== 0
  return (
    <>
      <SectionHeader
        title={failed ? 'La instalación se detuvo' : 'Instalando Ideas Box'}
        subtitle={failed ? 'Lo que ya quedó hecho está guardado. Revisá el detalle, resolvé lo que diga y reintentá desde el mismo paso.' : 'Podés dejar esta pestaña abierta y seguir con otra cosa: si hace falta algo, te lo preguntamos acá.'}
      />

      <div className="mb-5">
        <div className="h-1.5 bg-panel-raised">
          <div className={`h-full transition-all duration-700 ${failed ? 'bg-rose-500' : 'bg-accent'}`} style={{ width: `${Math.min(100, (doneCount / Math.max(1, total)) * 100)}%` }} />
        </div>
        <div className="mt-2 text-[12px] text-muted flex justify-between">
          <span className="truncate pr-4">{!failed && lastAction}</span>
          <span className="shrink-0">{doneCount} de {total} pasos</span>
        </div>
      </div>

      <Panel>
        {info.steps.filter((s) => !(info.skipDeps && s.id === 'deps')).map((s) => {
          const state = steps.st[s.id]
          return (
            <div key={s.id} className="flex items-center gap-3 px-5 py-3 border-b border-border last:border-b-0">
              <span className="w-5 flex justify-center">
                {state === 'done' && <span className="text-emerald-400 text-sm">✓</span>}
                {state === 'running' && (failed ? <span className="text-rose-400 text-sm">✗</span> : <Spinner />)}
                {state === 'failed' && <span className="text-rose-400 text-sm">✗</span>}
                {state === 'pending' && <span className="w-1.5 h-1.5 bg-border rounded-full" />}
              </span>
              <span className={`text-sm flex-1 ${state === 'pending' ? 'text-muted' : 'text-white'}`}>{s.label}</span>
              {state === 'running' && !failed && <Badge tone="accent">en curso</Badge>}
              {(state === 'failed' || (failed && state === 'running')) && <Badge tone="danger">se detuvo acá</Badge>}
            </div>
          )
        })}
      </Panel>

      {failed && (
        <div className="mt-5 space-y-3">
          <Callout tone="danger">
            <div className="font-medium mb-1">Qué dijo el instalador</div>
            <pre className="whitespace-pre-wrap font-mono text-[12px] text-rose-100/90 max-h-56 overflow-y-auto log-scroll">
              {logs.slice(-12).map((l) => l.text).join('\n')}
            </pre>
          </Callout>
          <div className="flex gap-2">
            <Button onClick={() => api.retry().catch((e) => alert(e.message))}>Reintentar desde este paso</Button>
            <Button variant="ghost" onClick={onEdit}>Cambiar mis respuestas</Button>
            <Button variant="ghost" onClick={() => setShowLog(true)}>Ver el detalle completo</Button>
          </div>
          <p className="text-[12px] text-muted">
            Si no sabés cómo seguir, mandanos el detalle completo (botón de arriba → copiar) y lo resolvemos con vos.
          </p>
        </div>
      )}

      <div className="mt-5">
        <button type="button" onClick={() => setShowLog(!showLog)} className="text-[13px] text-muted hover:text-white">
          {showLog ? '▾ Ocultar el detalle técnico' : '▸ Ver el detalle técnico'}
        </button>
        {showLog && (
          <Panel className="mt-2">
            <div className="flex justify-end px-3 py-1.5 border-b border-border">
              <button type="button" className="text-[12px] text-muted hover:text-white" onClick={() => navigator.clipboard?.writeText(logs.map((l) => l.text).join('\n'))}>
                Copiar
              </button>
            </div>
            <div ref={logRef} className="h-72 overflow-y-auto log-scroll px-4 py-3 font-mono text-[12px] leading-relaxed">
              {logs.map((l) => (
                <div key={l.seq} className={`whitespace-pre-wrap break-words ${lineTone(l.text)}`}>{l.text}</div>
              ))}
              {!failed && !exit && <div className="text-accent ib-pulse">▍</div>}
            </div>
          </Panel>
        )}
      </div>

      {pending && <AskModal ask={pending} />}
    </>
  )
}

// Pregunta del instalador que no estaba en los formularios (reintentar, esperar a Apple…)
function AskModal({ ask }: { ask: Ask }) {
  const [value, setValue] = useState(ask.type === 'confirm' ? '' : ask.default)
  const [busy, setBusy] = useState(false)
  const send = async (v: string) => {
    setBusy(true)
    try {
      await api.answer(v)
    } catch (e) {
      alert((e as Error).message)
      setBusy(false)
    }
  }
  const q = ask.question.replace(/\s*\[[sSnN]\/[sSnN]\]\s*$/, '').trim()
  if (ask.type === 'confirm') {
    const def = ask.default === 'y'
    return (
      <Modal
        title="El instalador te pregunta"
        footer={
          <>
            <Button variant={def ? 'ghost' : 'primary'} disabled={busy} onClick={() => send('n')}>No</Button>
            <Button variant={def ? 'primary' : 'ghost'} disabled={busy} onClick={() => send('s')}>Sí</Button>
          </>
        }
      >
        <p className="text-sm text-white leading-relaxed">{q}</p>
      </Modal>
    )
  }
  return (
    <Modal
      title="El instalador necesita un dato"
      footer={<Button disabled={busy} onClick={() => send(value)}>Continuar</Button>}
    >
      <form onSubmit={(e) => { e.preventDefault(); send(value) }}>
        <label className="block">
          <span className="text-sm text-white">{q}</span>
          <input
            autoFocus
            type={ask.type === 'secret' ? 'password' : 'text'}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            autoComplete="off"
            className="mt-2 w-full bg-ink border border-border px-3 py-2 text-sm text-white focus:outline-none focus:border-accent"
          />
        </label>
        {ask.type === 'secret' && <p className="text-[12px] text-muted mt-2">Queda guardada solo en tu equipo.</p>}
      </form>
    </Modal>
  )
}

function Done({ info, summary, panel, onClose }: { info: Info; summary?: { empresa: string; dataRoot: string }; panel: boolean; onClose: () => void }) {
  const [msg, setMsg] = useState('')
  const open = (what: 'panel' | 'folder') =>
    api.open(what).then(() => setMsg(what === 'panel' ? 'Abriendo el panel en otra pestaña…' : 'Abriendo la carpeta…')).catch((e) => setMsg(e.message))
  return (
    <>
      <SectionHeader title="¡Listo! Ideas Box quedó instalado" subtitle={summary?.empresa ? `El equipo de ${summary.empresa} ya tiene sus agentes.` : undefined} />
      <Panel className="p-5">
        <div className="text-[13px] text-white font-medium mb-2">En tu Escritorio</div>
        <ul className="text-[13px] text-muted space-y-1.5">
          <li><span className="text-white">Ideas Box</span> — el menú: hablar con tus agentes, conectar herramientas, crear habilidades.</li>
          <li><span className="text-white">Archivos Ideas Box</span> — todo lo que generan tus agentes, por área.</li>
          {panel && <li><span className="text-white">Panel Ideas Box</span> — tareas y programación de los agentes.</li>}
        </ul>
        {summary?.dataRoot && <div className="mt-3 text-[12px] text-muted">Tus datos: <span className="font-mono text-white">{summary.dataRoot}</span></div>}
      </Panel>
      <div className="mt-4">
        <Callout>
          La primera vez que hables con tus agentes, Claude te va a pedir iniciar sesión con tu cuenta.
          {info.mcps.some((m) => m.kind === 'remote') && ' Los conectores que se autorizan con tu cuenta (como Kling) te lo piden la primera vez que se usan.'}
        </Callout>
      </div>
      <div className="mt-6 flex gap-2 flex-wrap">
        {panel && <Button onClick={() => open('panel')}>Abrir el panel</Button>}
        <Button variant="ghost" onClick={() => open('folder')}>Abrir la carpeta de archivos</Button>
        <div className="flex-1" />
        <Button variant="ghost" onClick={onClose}>Cerrar el asistente</Button>
      </div>
      {msg && <p className="mt-3 text-[12px] text-muted">{msg}</p>}
    </>
  )
}
