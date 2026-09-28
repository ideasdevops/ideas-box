import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api, AREA, type Agente, type AgenteFicha } from '../api'
import { Badge, Button, Chips, EmptyState, Input, Modal, Panel, SectionHeader } from '../components/ui'
import { Markdown } from '../components/markdown'

const ORDEN = ['core', 'ventas', 'marketing', 'contenido', 'clientes', 'dev', 'ops', 'qa', 'internos']

function Ficha({ nombre, onClose }: { nombre: string; onClose: () => void }) {
  const navigate = useNavigate()
  const [f, setF] = useState<AgenteFicha | null>(null)
  const [ver, setVer] = useState(false)
  useEffect(() => { api.agent(nombre).then(setF) }, [nombre])
  const conversar = async () => {
    const h = await api.newHilo(nombre, 'carpeta')
    navigate(`/conversar/${h.id}`)
  }
  return (
    <Modal title={nombre} wide onClose={onClose}>
      {!f ? <div className="text-sm text-muted">Cargando…</div> : (
        <div className="space-y-5">
          <div className="flex items-start justify-between gap-4">
            <div>
              <div className="flex gap-2 mb-2"><Badge tone="accent">{AREA[f.dominio] ?? f.dominio}</Badge>{f.modelo && <Badge>modelo {f.modelo}</Badge>}</div>
              <p className="text-sm text-white/85">{f.descripcion}</p>
            </div>
            <div className="flex gap-2 shrink-0">
              <Button onClick={conversar}>Conversar</Button>
              <Button variant="ghost" onClick={() => navigate(`/tareas?nueva=1&agente=${encodeURIComponent(nombre)}`)}>Darle una tarea</Button>
            </div>
          </div>
          <div>
            <div className="text-xs uppercase tracking-wider text-muted mb-2">Con qué puede trabajar</div>
            <div className="space-y-2">
              {f.conectores.map((c) => (
                <div key={c.conector} className="flex gap-3 text-xs">
                  <span className="w-36 shrink-0 text-white">{c.conector === 'básicas' ? 'Herramientas básicas' : c.conector}</span>
                  <div className="flex flex-wrap gap-1">{c.herramientas.map((h) => <span key={h} className="px-1.5 py-0.5 bg-panel-raised text-muted">{h}</span>)}</div>
                </div>
              ))}
              {f.conectores.every((c) => c.conector === 'básicas') && (
                <div className="text-[11px] text-muted">Sin conectores externos. Si instalás uno que le sirve a este agente, lo recibe solo.</div>
              )}
            </div>
          </div>
          {f.skills.length > 0 && (
            <div>
              <div className="text-xs uppercase tracking-wider text-muted mb-2">Habilidades que usa</div>
              <div className="flex flex-wrap gap-1.5">{f.skills.map((s) => <Badge key={`${s.dominio}/${s.carpeta}`}>{s.dominio}/{s.carpeta}</Badge>)}</div>
            </div>
          )}
          <div>
            <button onClick={() => setVer(!ver)} className="text-xs text-muted hover:text-white">{ver ? '▾ Ocultar' : '▸ Ver'} sus instrucciones completas</button>
            {ver && <div className="mt-2 border border-border bg-panel-raised p-4 max-h-[50vh] overflow-y-auto"><Markdown text={f.instrucciones} /></div>}
            <div className="text-[11px] text-muted mt-2">Se editan en <span className="font-mono">{f.archivo}</span></div>
          </div>
        </div>
      )}
    </Modal>
  )
}

export default function AgentesPage() {
  const [agentes, setAgentes] = useState<Agente[] | null>(null)
  const [area, setArea] = useState('todas')
  const [q, setQ] = useState('')
  const [abierto, setAbierto] = useState<string | null>(null)
  useEffect(() => { api.agents().then((r) => setAgentes(r.agentes)) }, [])
  if (!agentes) return <EmptyState label="Cargando…" />

  const areas = ORDEN.filter((a) => agentes.some((x) => x.dominio === a))
  const filtrados = agentes.filter((a) =>
    (area === 'todas' || a.dominio === area) &&
    (!q || `${a.nombre} ${a.descripcion}`.toLowerCase().includes(q.toLowerCase())))
  const grupos = areas.map((ar) => [ar, filtrados.filter((a) => a.dominio === ar)] as const).filter(([, v]) => v.length)

  return (
    <div>
      <SectionHeader title="Tu equipo de agentes" subtitle={`${agentes.length} agentes, uno por área. Tocá uno para ver qué hace y con qué trabaja.`}
        action={<Input placeholder="Buscar…" value={q} onChange={(e) => setQ(e.target.value)} className="!w-64" />} />
      <div className="mb-5">
        <Chips value={area} onChange={setArea} options={[{ value: 'todas', label: 'Todas las áreas' }, ...areas.map((a) => ({ value: a, label: AREA[a] ?? a }))]} />
      </div>
      {grupos.length === 0 && <EmptyState label="Ningún agente coincide." />}
      <div className="space-y-7">
        {grupos.map(([ar, items]) => (
          <section key={ar}>
            <div className="text-xs uppercase tracking-wider text-muted mb-2">{AREA[ar] ?? ar}</div>
            <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-3">
              {items.map((a) => {
                const externos = a.conectores.filter((c) => c.conector !== 'básicas')
                return (
                  <button key={a.nombre} onClick={() => setAbierto(a.nombre)} className="text-left">
                    <Panel className="p-4 h-full hover:border-accent/50 transition-colors">
                      <div className="text-sm font-medium text-white mb-1">{a.nombre}</div>
                      <p className="text-xs text-muted leading-relaxed line-clamp-3">{a.descripcion}</p>
                      <div className="mt-3 flex flex-wrap gap-1">
                        {externos.slice(0, 4).map((c) => <Badge key={c.conector}>{c.conector}</Badge>)}
                        {externos.length > 4 && <Badge>+{externos.length - 4}</Badge>}
                        {externos.length === 0 && <span className="text-[11px] text-muted/70">sin conectores externos</span>}
                      </div>
                    </Panel>
                  </button>
                )
              })}
            </div>
          </section>
        ))}
      </div>
      {abierto && <Ficha nombre={abierto} onClose={() => setAbierto(null)} />}
    </div>
  )
}
