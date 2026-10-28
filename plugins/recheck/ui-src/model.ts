/** Ответ метода status (rpc/recheck) и разбор памяти движка для экрана обучения. */
export interface Status {
  running: boolean
  version: string
  wan: string
  wan_dev: string
  strict: boolean
  persist: boolean
  learned: number
  confirmed: number
  queued: number
  watched: number
  /** Файл памяти движка как есть (строки E — сайты). */
  state: string
  /** Последние события движка: event=<что> … host= ip= port=. */
  events: string
}

export interface Site { host: string; ip: string; port: number; proto: 'TCP' | 'UDP'; confirmed: boolean }
export interface Event { what: string; host: string; ip: string; port: number }

/** Строка памяти: E <эпоха> <подтверждён> <семейство> <протокол> <порт> <рецепт> <…> <ip> <имя> <…>. */
export function sites(state: string): Site[] {
  const out: Site[] = []
  for (const line of state.split('\n')) {
    const f = line.trim().split(/\s+/)
    if (f[0] !== 'E' || f.length < 10) continue
    out.push({ host: f[9] === '-' ? '' : f[9], ip: f[8], port: Number(f[5]) || 0, proto: f[4] === '17' ? 'UDP' : 'TCP', confirmed: f[2] === '1' })
  }
  return out.sort((a, b) => Number(b.confirmed) - Number(a.confirmed) || (a.host || a.ip).localeCompare(b.host || b.ip))
}

export function events(text: string): Event[] {
  const out: Event[] = []
  for (const line of text.split('\n')) {
    const m = /^event=([a-z-]+) .*host=(\S*) ip=(\S*) port=(\d+)/.exec(line)
    if (m) out.push({ what: m[1], host: m[2], ip: m[3], port: Number(m[4]) })
  }
  return out.reverse()
}
