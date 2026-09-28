// Markdown mínimo para las respuestas de los agentes: títulos, listas, código,
// negritas, cursivas y enlaces. Arma elementos de React (nunca innerHTML), así un
// texto con HTML adentro se muestra como texto y no se ejecuta.
import type { ReactNode } from 'react'

function inline(text: string, key: string): ReactNode[] {
  const out: ReactNode[] = []
  const re = /(`[^`]+`|\*\*[^*]+\*\*|\*[^*\s][^*]*\*|\[[^\]]+\]\((https?:\/\/[^)\s]+)\))/g
  let last = 0
  let m: RegExpExecArray | null
  let i = 0
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(text.slice(last, m.index))
    const tok = m[0]
    const k = `${key}-${i++}`
    if (tok.startsWith('`')) out.push(<code key={k} className="px-1 bg-panel-raised text-accent text-[0.9em]">{tok.slice(1, -1)}</code>)
    else if (tok.startsWith('**')) out.push(<strong key={k} className="text-white">{tok.slice(2, -2)}</strong>)
    else if (tok.startsWith('[')) {
      const label = tok.slice(1, tok.indexOf(']'))
      out.push(<a key={k} href={m[2]} target="_blank" rel="noreferrer" className="text-accent underline underline-offset-2">{label}</a>)
    } else out.push(<em key={k}>{tok.slice(1, -1)}</em>)
    last = m.index + tok.length
  }
  if (last < text.length) out.push(text.slice(last))
  return out
}

export function Markdown({ text, className = '' }: { text: string; className?: string }) {
  const lines = (text || '').replace(/\r/g, '').split('\n')
  const blocks: ReactNode[] = []
  let i = 0
  let list: { ordered: boolean; items: string[] } | null = null
  const flushList = () => {
    if (!list) return
    const Tag = list.ordered ? 'ol' : 'ul'
    blocks.push(
      <Tag key={`l${blocks.length}`} className={`${list.ordered ? 'list-decimal' : 'list-disc'} pl-5 space-y-0.5`}>
        {list.items.map((it, j) => <li key={j}>{inline(it, `li${blocks.length}-${j}`)}</li>)}
      </Tag>,
    )
    list = null
  }
  while (i < lines.length) {
    const line = lines[i]
    if (line.trim().startsWith('```')) {
      flushList()
      const code: string[] = []
      i++
      while (i < lines.length && !lines[i].trim().startsWith('```')) code.push(lines[i++])
      i++
      blocks.push(<pre key={`c${blocks.length}`} className="bg-ink border border-border p-3 text-xs overflow-x-auto text-white/90">{code.join('\n')}</pre>)
      continue
    }
    const h = /^(#{1,4})\s+(.*)$/.exec(line)
    const ul = /^\s*[-*•]\s+(.*)$/.exec(line)
    const ol = /^\s*\d+[.)]\s+(.*)$/.exec(line)
    if (h) {
      flushList()
      const size = h[1].length <= 2 ? 'text-base' : 'text-sm'
      blocks.push(<div key={`h${blocks.length}`} className={`${size} font-medium text-white mt-2`}>{inline(h[2], `h${i}`)}</div>)
    } else if (ul || ol) {
      const ordered = Boolean(ol)
      if (!list || list.ordered !== ordered) {
        flushList()
        list = { ordered, items: [] }
      }
      list.items.push((ul || ol)![1])
    } else if (/^\s*(---|\*\*\*)\s*$/.test(line)) {
      flushList()
      blocks.push(<hr key={`r${blocks.length}`} className="border-border" />)
    } else if (line.trim() === '') {
      flushList()
    } else {
      flushList()
      blocks.push(<p key={`p${blocks.length}`}>{inline(line, `p${i}`)}</p>)
    }
    i++
  }
  flushList()
  return <div className={`space-y-2 text-sm leading-relaxed text-white/85 break-words ${className}`}>{blocks}</div>
}
