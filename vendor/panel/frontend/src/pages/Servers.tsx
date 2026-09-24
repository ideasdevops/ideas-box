import { useEffect, useState } from 'react'
import { api, type ServerEntry } from '../api'
import { Badge, EmptyState, Panel, SectionHeader } from '../components/ui'

export default function ServersPage() {
  const [servers, setServers] = useState<ServerEntry[] | null>(null)

  useEffect(() => {
    api.servers().then((r) => setServers(r.servers))
  }, [])

  return (
    <div>
      <SectionHeader
        title="Servidores"
        subtitle="Salen de los conectores MCP instalados — se agregan con: ideasbox mcp add"
      />

      {!servers && <EmptyState label="Cargando..." />}
      {servers?.length === 0 && (
        <EmptyState label="Todavía no hay servidores conectados. Agregá uno con: ideasbox mcp add ssh-infra" />
      )}

      <div className="grid grid-cols-4 gap-2">
        {servers?.map((s) => (
          <Panel key={s.alias} className="p-3">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-white">{s.label}</span>
            </div>
            <div className="flex flex-wrap gap-1 mt-2">
              {s.toolgroups.map((g) => (
                <Badge key={g} tone="accent">
                  {g}
                </Badge>
              ))}
            </div>
            <div className="text-[11px] text-muted mt-2 space-y-0.5">
              {s.mcps.map((m) => (
                <div key={m}>{m}</div>
              ))}
            </div>
          </Panel>
        ))}
      </div>
    </div>
  )
}
