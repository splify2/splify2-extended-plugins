// Чистая логика плагина: разбор ключей выхода WARP в спеке и правки выхода. Без интерфейса — проверяется
// стендом tests/model.test.ts.
import type { OutputV2, SpecV2 } from '@splify2/plugin-api'

/** Число из спеки: рукописный файл бывает со строкой («count: "3"») — ядро её читает, экран обязан тоже. */
export const num = (v: unknown, d: number): number => {
  const n = typeof v === 'string' && v.trim() ? Number(v) : v
  return typeof n === 'number' && Number.isFinite(n) ? n : d
}

/** Сколько туннелей в группе по спеке: целое от 1 (steer docs/warp.md: 1..255). */
export const tunnelCount = (v: unknown): number => Math.max(1, Math.trunc(num(v, 1)))

/** Коды стран из ключа спеки: строка или список; чужие значения отбрасываются. */
export const codes = (v: unknown): string[] | undefined => {
  if (typeof v === 'string') return /^[A-Za-z]{2}$/.test(v) ? [v.toUpperCase()] : undefined
  return Array.isArray(v) ? v.filter((c): c is string => typeof c === 'string').map((c) => c.toUpperCase()) : undefined
}

export const isWarp = (o: OutputV2 | undefined): boolean => !!o && o.kind === 'warp'

/** Выходы `kind: warp` спеки по именам. */
export function warpOutputs(spec: SpecV2 | null): [string, OutputV2][] {
  return Object.entries(spec?.outputs ?? {}).filter(([, o]) => isWarp(o))
}

/** Первое свободное имя выхода: warp, warp2, warp3… */
export function freeName(outputs: Record<string, unknown> | undefined): string {
  const o = outputs ?? {}
  if (!o.warp) return 'warp'
  for (let i = 2; ; i++) if (!o[`warp${i}`]) return `warp${i}`
}

/** Имя нового выхода: ядро держит имена туннелей «<имя>.<n>», поэтому имя короткое. */
export const nameOk = (n: string): boolean => /^[a-z][a-z0-9_-]{0,14}$/.test(n)

/** Ключ выхода `warp`, которым закрепляют точку входа («адрес:порт»; нет ключа — модуль подбирает сам).
 *  ТРЕБУЕТ ЯДРО: в спеке v2 (spec-v2.md, kind warp) такого ключа пока нет; пока его нет, ядро отвечает на
 *  него отказом проверки, и отказ виден человеку там же, где отказы других правок. */
export const ENDPOINT_KEY = 'endpoint'

/** Закреплённая точка выхода или '' . */
export function pinnedPoint(o: OutputV2 | undefined): string {
  const v = o?.[ENDPOINT_KEY]
  return typeof v === 'string' ? v : ''
}

/** Правка ключей выхода на копии спеки. Ключ без значения (`undefined`) убирается — умолчание ядра. */
export function patchOutput(draft: SpecV2, name: string, patch: Record<string, unknown>): boolean {
  const o = draft.outputs?.[name]
  if (!o) return false
  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) delete o[k]
    else o[k] = v
  }
  return true
}

/** Настройки плагина «для новых выходов» (метод defaults_get). */
export interface Defaults {
  transport: 'awg' | 'masque'
  count: number
  pick: 'latency' | 'order'
  exclude_countries: string
}

export const DEFAULTS: Defaults = { transport: 'awg', count: 1, pick: 'latency', exclude_countries: '' }

/** Новый выход по настройкам: ключи, равные умолчанию ядра, не пишутся — спека остаётся короткой. */
export function newOutput(d: Defaults): OutputV2 {
  const o: OutputV2 = { kind: 'warp' }
  if (d.transport === 'masque') o.transport = 'masque'
  if (d.count > 1) o.count = d.count
  if (d.pick === 'order') o.pick = 'order'
  const ex = d.exclude_countries.split(',').map((c) => c.trim().toUpperCase()).filter((c) => /^[A-Z]{2}$/.test(c))
  if (ex.length && d.transport !== 'masque') o.exclude_countries = [...new Set(ex)]
  return o
}

/** Кнопки числа туннелей: 1–5, а если в спеке больше (до 255) — и это число, чтобы выбор был виден. */
export function countItems(count: number): { value: string; label: string }[] {
  const vals = [1, 2, 3, 4, 5]
  if (!vals.includes(count)) vals.push(count)
  return vals.map((v) => ({ value: String(v), label: String(v) }))
}

/** Точка «адрес:порт»; у MASQUE адрес бывает IPv6 — тогда в скобках. */
export const hostPort = (ip: string, port?: number): string => `${ip.includes(':') ? `[${ip}]` : ip}${port ? `:${port}` : ''}`

/** Что ядро знает о группе: `status.outputs.<выход>.group.warp` (поля нет — модуль старше). */
export interface WarpStatus {
  mask?: string
  why?: string
  members?: { out: string; ip?: string; port?: number; colo?: string; seen?: string; ok?: boolean }[]
}

export interface ScanPoint { ip: string; port?: number; class?: number; loss?: number; rtt?: number; colo?: string; cc?: string; ok?: boolean; error?: string }
export interface ScanResult { ok?: boolean; error?: string; points?: ScanPoint[]; filtered?: number; transport?: string }
export interface ScanState { running: boolean; at: number; result: ScanResult | null }

/** Сколько туннелей из группы отвечает, по `status`: (работает, всего). */
export function tunnelsUp(count: number, st: { group?: { alive?: string[]; selected?: string | null } } | undefined): [number, number] {
  const alive = st?.group?.alive?.length ?? 0
  return [alive || (st?.group?.selected ? 1 : 0), count]
}
