import { useEffect, useState } from 'react'
import { api, type Ajustes, type ConectorCatalogo, type Mantenimiento } from '../api'
import { RunBadge, RunView, usePoll } from '../components/run'
import { Badge, Button, EmptyState, Field, Input, Modal, Panel, SectionHeader, Select } from '../components/ui'

const DESCRIPCION: Record<string, string> = {
  revisar: 'Diagnóstico de disco, agentes, enlaces, conectores y credenciales.',
  'revisar-profundo': 'Igual que revisar, pero arranca cada conector para comprobar que responde.',
  sincronizar: 'Regenera agentes y documentación y repara enlaces. No pisa lo que editaste.',
  actualizar: 'Trae la última versión de Ideas Box, las habilidades y los conectores.',
  'actualizar-habilidades': 'Solo los packs de habilidades.',
  respaldo: 'Copia comprimida de agentes, memoria y configuración (incluye credenciales: guardala cifrada).',
  iconos: 'Vuelve a crear los accesos del Escritorio.',
  'actualizar-panel': 'Instala la última versión de este panel. Después hay que reiniciarlo.',
}

function Conectar({ c, onClose, onRun }: { c: ConectorCatalogo; onClose: () => void; onRun: (id: number) => void }) {
  const [claves, setClaves] = useState<Record<string, string>>({})
  const [etiqueta, setEtiqueta] = useState('')
  const [login, setLogin] = useState(true)
  return (
    <Modal title={`Conectar ${c.titulo.split(' — ')[0]}`} onClose={onClose}>
      <p className="text-sm text-muted mb-4">{c.descripcion}</p>
      <div className="space-y-3">
        {c.multi && <Field label={c.etiqueta || 'Etiqueta de esta cuenta'} hint="Para distinguirla si sumás más de una."><Input value={etiqueta} onChange={(e) => setEtiqueta(e.target.value)} /></Field>}
        {c.campos.map((f) => (
          <Field key={f.clave} label={f.texto} hint={f.secreto ? 'Se guarda solo en tu equipo, en un archivo que solo tu usuario puede leer. No queda en el historial.' : undefined}>
            <Input type={f.secreto ? 'password' : 'text'} autoComplete="off" value={claves[f.clave] ?? ''} onChange={(e) => setClaves({ ...claves, [f.clave]: e.target.value })} />
          </Field>
        ))}
        {c.login && (
          <label className="flex items-center gap-2 text-sm text-white">
            <input type="checkbox" checked={login} onChange={(e) => setLogin(e.target.checked)} /> Conectar mi cuenta ahora (se abre el navegador)
          </label>
        )}
        {c.tipo === 'remote' && <div className="text-xs text-muted">Se autoriza con tu cuenta la primera vez que un agente lo use.</div>}
        {c.campos.length === 0 && !c.login && c.tipo !== 'remote' && <div className="text-xs text-muted">No necesita claves.</div>}
      </div>
      <div className="mt-5 flex justify-end gap-2">
        <Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button onClick={async () => { const { run_id } = await api.maint({ accion: 'conectar', conector: c.id, etiqueta, claves, login }); onRun(run_id); onClose() }}>Conectar</Button>
      </div>
    </Modal>
  )
}

export default function MantenimientoPage() {
  const [m, setM] = useState<Mantenimiento | null>(null)
  const [ajustes, setAjustes] = useState<Ajustes | null>(null)
  const [runVisible, setRunVisible] = useState<number | null>(null)
  const [conectar, setConectar] = useState<ConectorCatalogo | null>(null)
  const [reiniciando, setReiniciando] = useState(false)
  const { data: recientes, recargar } = usePoll(() => api.runs({ tipo: 'mantenimiento', limite: 8 }), 4000)

  const cargar = () => api.mantenimiento().then(setM)
  useEffect(() => { cargar(); api.ajustes().then(setAjustes) }, [])

  const correr = async (accion: string, extra: Record<string, string> = {}) => {
    const { run_id } = await api.maint({ accion, ...extra })
    setRunVisible(run_id)
    recargar()
  }
  const reiniciar = async () => {
    setReiniciando(true)
    await api.restart()
    const esperar = async () => {
      try { await api.profile(); window.location.reload() } catch { setTimeout(esperar, 1500) }
    }
    setTimeout(esperar, 3000)
  }

  if (!m) return <EmptyState label="Cargando…" />
  const instalados = m.conectores.filter((c) => c.instalado.length)
  const disponibles = m.conectores.filter((c) => !c.instalado.length && c.nivel !== 'core')

  return (
    <div>
      <SectionHeader title="Mantenimiento" subtitle="Todo lo del menú de Ideas Box, sin terminal. Cada acción muestra su avance en vivo." />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-3 mb-8">
        {m.acciones.map((a) => (
          <Panel key={a.id} className="p-4 flex items-center gap-4">
            <div className="flex-1 min-w-0">
              <div className="text-sm text-white">{a.titulo}</div>
              <div className="text-xs text-muted mt-0.5">{DESCRIPCION[a.id]}</div>
            </div>
            <Button small variant={a.id === 'revisar' ? 'primary' : 'ghost'} onClick={() => correr(a.id)}>Hacerlo</Button>
          </Panel>
        ))}
        <Panel className="p-4 flex items-center gap-4">
          <div className="flex-1">
            <div className="text-sm text-white">Reiniciar el panel</div>
            <div className="text-xs text-muted mt-0.5">Después de actualizarlo. Tarda unos segundos y la página se recarga sola.</div>
          </div>
          <Button small variant="ghost" onClick={reiniciar} disabled={reiniciando}>{reiniciando ? 'Reiniciando…' : 'Reiniciar'}</Button>
        </Panel>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6 mb-8">
        <section>
          <h2 className="text-xs uppercase tracking-wider text-muted mb-2">Arranque y ejecución</h2>
          <Panel className="p-4 space-y-4">
            <label className="flex items-start gap-3">
              <input type="checkbox" className="mt-1" checked={m.autostart} onChange={(e) => api.autostart(e.target.checked).then(cargar).catch((er) => alert(er.message))} />
              <span>
                <span className="text-sm text-white block">Abrir el panel solo al iniciar sesión</span>
                <span className="text-xs text-muted">Para que las tareas programadas corran aunque no te acuerdes de abrirlo.</span>
              </span>
            </label>
            {ajustes && (
              <div className="grid grid-cols-2 gap-4">
                <Field label="Modelo para las ejecuciones del panel" hint="«El de cada agente» respeta lo que define cada uno.">
                  <Select value={ajustes.modelo} onChange={(e) => api.saveAjustes({ modelo: e.target.value }).then(setAjustes)}>
                    <option value="">El de cada agente</option>
                    <option value="sonnet">Sonnet (equilibrado)</option>
                    <option value="opus">Opus (el más capaz, más costoso)</option>
                    <option value="haiku">Haiku (rápido y económico)</option>
                  </Select>
                </Field>
                <Field label="Límite de pasos por ejecución" hint="Frena a un agente que se enreda.">
                  <Input type="number" min={5} max={200} value={ajustes.max_turnos} onChange={(e) => setAjustes({ ...ajustes, max_turnos: Number(e.target.value) })}
                    onBlur={() => api.saveAjustes({ max_turnos: ajustes.max_turnos }).then(setAjustes)} />
                </Field>
              </div>
            )}
          </Panel>

          <h2 className="text-xs uppercase tracking-wider text-muted mb-2 mt-6">Últimas acciones</h2>
          <div className="space-y-1">
            {(recientes?.ejecuciones ?? []).length === 0 && <div className="text-xs text-muted">Todavía no corriste ninguna.</div>}
            {recientes?.ejecuciones.map((r) => (
              <button key={r.id} onClick={() => setRunVisible(r.id)} className="w-full text-left flex items-center gap-3 px-3 py-2 border border-border hover:border-accent/40 text-sm">
                <RunBadge estado={r.estado} />
                <span className="text-white truncate flex-1">{r.titulo}</span>
                <span className="text-[11px] text-muted">{r.fin?.slice(5, 16) ?? ''}</span>
              </button>
            ))}
          </div>
        </section>

        <section>
          <h2 className="text-xs uppercase tracking-wider text-muted mb-2">Herramientas conectadas</h2>
          <div className="space-y-1 mb-5">
            {instalados.map((c) => (
              <div key={c.id} className="flex items-center gap-3 px-3 py-2 border border-border text-sm">
                <span className="text-white flex-1 truncate">{c.titulo.split(' — ')[0]}</span>
                <span className="text-[11px] text-muted truncate">{c.instalado.join(', ')}</span>
                {c.campos.length > 0 && <Button small variant="ghost" onClick={() => setConectar(c)}>{c.multi ? 'Otra cuenta' : 'Cambiar claves'}</Button>}
                {c.nivel !== 'core' && c.instalado.map((srv) => (
                  <Button key={srv} small variant="quiet" onClick={() => confirm(`¿Quitar el conector ${srv}?`) && correr('quitar-conector', { servidor: srv }).then(cargar)}>Quitar</Button>
                ))}
              </div>
            ))}
          </div>
          <h2 className="text-xs uppercase tracking-wider text-muted mb-2">Para conectar</h2>
          <div className="space-y-1 mb-5">
            {disponibles.map((c) => (
              <div key={c.id} className="flex items-center gap-3 px-3 py-2 border border-border text-sm">
                <div className="flex-1 min-w-0">
                  <div className="text-white truncate">{c.titulo.split(' — ')[0]} {c.recomendado && <Badge tone="accent">recomendado</Badge>}</div>
                  <div className="text-[11px] text-muted truncate">{c.descripcion}</div>
                </div>
                <Button small variant="ghost" onClick={() => setConectar(c)}>Conectar</Button>
              </div>
            ))}
          </div>
          <h2 className="text-xs uppercase tracking-wider text-muted mb-2">Sumar habilidades</h2>
          <div className="space-y-1">
            {m.packs.map((p) => (
              <div key={p.id} className="flex items-center gap-3 px-3 py-2 border border-border text-sm">
                <div className="flex-1 min-w-0">
                  <div className="text-white">{p.id} <span className="text-[11px] text-muted">· {p.area}</span></div>
                  <div className="text-[11px] text-muted truncate">{p.descripcion}</div>
                </div>
                <Button small variant="ghost" onClick={() => correr('sumar-habilidad', { pack: p.id })}>Sumar / actualizar</Button>
              </div>
            ))}
          </div>
        </section>
      </div>

      {conectar && <Conectar c={conectar} onClose={() => setConectar(null)} onRun={(id) => { setRunVisible(id); recargar() }} />}
      {runVisible && <Modal title="Mantenimiento" wide onClose={() => { setRunVisible(null); cargar(); recargar() }}><RunView runId={runVisible} onChanged={recargar} /></Modal>}
    </div>
  )
}
