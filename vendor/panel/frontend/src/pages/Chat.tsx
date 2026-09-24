import { useEffect, useRef, useState } from 'react'
import { api, type ChatMessageRow } from '../api'
import { Badge, Panel, SectionHeader } from '../components/ui'

export default function ChatPage() {
  const [mensajes, setMensajes] = useState<ChatMessageRow[]>([])
  const [input, setInput] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    api.chatHistory().then((r) => setMensajes(r.mensajes))
  }, [])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [mensajes])

  const enviar = async () => {
    const texto = input.trim()
    if (!texto || enviando) return
    setError(null)
    setInput('')
    setMensajes((prev) => [
      ...prev,
      { id: -1, rol: 'usuario', texto, tarea_creada_id: null, creado_en: new Date().toISOString() },
    ])
    setEnviando(true)
    try {
      const { respuesta, tarea_creada } = await api.sendChatMessage(texto)
      setMensajes((prev) => [
        ...prev,
        {
          id: -2,
          rol: 'asistente',
          texto: respuesta,
          tarea_creada_id: tarea_creada?.id ?? null,
          tarea_titulo: tarea_creada?.titulo ?? null,
          tarea_agente: tarea_creada?.agente_sugerido ?? null,
          creado_en: new Date().toISOString(),
        },
      ])
    } catch (e) {
      setError(String(e))
    } finally {
      setEnviando(false)
    }
  }

  return (
    <div className="flex flex-col h-[calc(100vh-4rem)]">
      <SectionHeader
        title="Chat"
        subtitle="Contame en lenguaje natural qué necesitás — interpreto el pedido y creo la tarea ruteada al agente correcto"
      />
      <Panel className="flex-1 flex flex-col overflow-hidden">
        <div className="flex-1 overflow-y-auto p-4 space-y-3">
          {mensajes.length === 0 && (
            <div className="text-sm text-muted text-center py-12">
              Ej: "necesito un post para Instagram sobre el lanzamiento de la promo de primavera"
            </div>
          )}
          {mensajes.map((m) => (
            <div key={m.id} className={`flex flex-col gap-1.5 ${m.rol === 'usuario' ? 'items-end' : 'items-start'}`}>
              <div
                className={`max-w-lg px-3 py-2 text-sm whitespace-pre-wrap ${
                  m.rol === 'usuario' ? 'bg-accent text-black' : 'bg-panel-raised text-white border border-border'
                }`}
              >
                {m.texto}
              </div>
              {m.tarea_creada_id && (
                <div className="border border-accent/30 bg-accent/5 px-3 py-1.5 text-xs text-accent max-w-md">
                  Tarea creada: <span className="font-medium">{m.tarea_titulo}</span>
                  {m.tarea_agente && <> — agente: {m.tarea_agente}</>}
                  {' '}<Badge tone="accent">ver en Tareas</Badge>
                </div>
              )}
            </div>
          ))}
          {enviando && <div className="text-xs text-muted">pensando...</div>}
          {error && <div className="text-xs text-rose-400">{error}</div>}
          <div ref={bottomRef} />
        </div>
        <div className="border-t border-border p-3 flex gap-2">
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && enviar()}
            placeholder="Escribí tu pedido..."
            className="flex-1 bg-panel-raised border border-border px-3 py-2 text-sm text-white placeholder:text-muted focus:outline-none focus:border-accent"
          />
          <button
            onClick={enviar}
            disabled={enviando}
            className="bg-accent text-black text-sm font-medium px-4 py-2 disabled:opacity-50"
          >
            Enviar
          </button>
        </div>
      </Panel>
    </div>
  )
}
