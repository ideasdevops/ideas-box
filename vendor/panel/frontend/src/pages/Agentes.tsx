import { useEffect, useState } from 'react'
import { api, type Agente } from '../api'
import { Badge, Panel, SectionHeader, EmptyState } from '../components/ui'

const DOMAIN_LABEL: Record<string, string> = {
  core: 'Core', dev: 'Desarrollo', ops: 'Operaciones', qa: 'QA', ventas: 'Ventas',
  marketing: 'Marketing', contenido: 'Contenido', clientes: 'Clientes', internos: 'Internos',
}

export default function AgentesPage() {
  const [agentes, setAgentes] = useState<Agente[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api.agents().then((r) => setAgentes(r.agentes)).catch((e) => setError(String(e)))
  }, [])

  if (error) return <EmptyState label={`Error cargando agentes: ${error}`} />
  if (!agentes) return <EmptyState label="Cargando..." />

  const byDomain = agentes.reduce<Record<string, Agente[]>>((acc, a) => {
    ;(acc[a.dominio] ??= []).push(a)
    return acc
  }, {})

  return (
    <div>
      <SectionHeader title="Agentes disponibles" subtitle={`${agentes.length} agentes en la raíz de datos del stack`} />
      <div className="space-y-8">
        {Object.entries(byDomain).map(([dominio, items]) => (
          <div key={dominio}>
            <div className="text-xs uppercase tracking-wider text-muted mb-2">{DOMAIN_LABEL[dominio] ?? dominio}</div>
            <div className="grid grid-cols-2 gap-3">
              {items.map((a) => (
                <Panel key={a.nombre} className="p-4">
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-medium text-white text-sm">{a.nombre}</span>
                    <Badge>{dominio}</Badge>
                  </div>
                  <p className="text-sm text-muted leading-relaxed">{a.descripcion}</p>
                </Panel>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
