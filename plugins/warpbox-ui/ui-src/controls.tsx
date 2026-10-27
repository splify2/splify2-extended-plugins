import type { Host, OutputV2 } from '@splify2/plugin-api'
import { useState } from 'preact/hooks'
import { codes, countItems, tunnelCount } from './model'

/** Страны, которые чаще всего берут. Остальные — вводом кода. */
const QUICK = ['RU', 'NL', 'DE', 'FI', 'SE', 'PL', 'GB', 'FR', 'US']

type Set = (patch: Record<string, unknown>) => void

/** Ключи выхода WARP: число туннелей, выбор туннеля, протокол, страна. `set` — правка ключей (undefined убирает ключ). */
export function Controls({ host, o, set }: { host: Host; o: OutputV2; set: Set }) {
  const { Segmented } = host.ui
  const t = host.i18n.t
  const count = tunnelCount(o.count)
  const pick = o.pick === 'order' ? 'order' : 'latency'
  const transport = o.transport === 'masque' ? 'masque' : 'awg'
  const only = codes(o.countries)
  const except = codes(o.exclude_countries)
  const tile = (title: string, body: unknown) => (
    <div class="warpbox-ui__tile">
      <div class="warpbox-ui__tile-title">{title}</div>
      {body as never}
    </div>
  )
  return (
    <div class="warpbox-ui__controls">
      {tile(t('count.title'), (
        <Segmented label={t('count.title')} value={String(count)} items={countItems(count)}
          onChange={(v) => set({ count: Number(v) === 1 ? undefined : Number(v) })} />
      ))}
      {tile(t('pick.title'), (
        <Segmented label={t('pick.title')} value={pick}
          items={[{ value: 'latency', label: t('pick.latency') }, { value: 'order', label: t('pick.order') }]}
          onChange={(v) => set({ pick: v === 'latency' ? undefined : v })} />
      ))}
      {tile(t('country.title'), transport === 'masque' ? (
        /* У MASQUE точку входа назначает Cloudflare, страну подбором не сменить. */
        <div class="warpbox-ui__note">
          {t('country.masque')}{only?.length || except?.length ? t('country.masqueSet') : ''}
        </div>
      ) : (
        <Countries host={host} only={only} except={except} onChange={(a, b) => set({ countries: a, exclude_countries: b })} />
      ))}
      {tile(t('transport.title'), (
        <Segmented label={t('transport.title')} value={transport}
          items={[{ value: 'awg', label: 'AmneziaWG' }, { value: 'masque', label: 'MASQUE' }]}
          onChange={(v) => set({ transport: v === 'awg' ? undefined : v })} />
      ))}
    </div>
  )
}

/** Страны: «любая, кроме…» или «только…». */
function Countries({ host, only, except, onChange }: {
  host: Host
  only?: string[]
  except?: string[]
  onChange: (only: string[] | undefined, except: string[] | undefined) => void
}) {
  const { Segmented, Chip, Flag, inputClass } = host.ui
  const t = host.i18n.t
  const mode = only?.length ? 'only' : 'except'
  const list = mode === 'only' ? only ?? [] : except ?? []
  const [code, setCode] = useState('')
  const put = (next: string[]) => (mode === 'only'
    ? onChange(next.length ? next : undefined, undefined)
    : onChange(undefined, next.length ? next : undefined))
  const add = (c: string) => {
    const cc = c.trim().toUpperCase()
    if (!/^[A-Z]{2}$/.test(cc) || list.includes(cc)) return
    put([...list, cc])
    setCode('')
  }
  return (
    <div class="warpbox-ui__countries">
      <Segmented label={t('country.title')} value={mode}
        items={[{ value: 'except', label: t('country.except') }, { value: 'only', label: t('country.only') }]}
        onChange={(m) => (m === 'only' ? onChange(['NL'], undefined) : onChange(undefined, undefined))} />
      <div class="warpbox-ui__chips">
        {list.map((c) => (
          <Chip key={c} on onClick={() => put(list.filter((x) => x !== c))}>
            <Flag cc={c} /> {c} <span aria-label={t('country.remove', { code: c })}>×</span>
          </Chip>
        ))}
        {list.length === 0 && <span class="warpbox-ui__note">{mode === 'except' ? t('country.none') : ''}</span>}
      </div>
      <div class="warpbox-ui__chips">
        {QUICK.filter((c) => !list.includes(c)).map((c) => (
          <Chip key={c} on={false} onClick={() => add(c)}><Flag cc={c} /> {c}</Chip>
        ))}
        <form onSubmit={(e) => { e.preventDefault(); add(code) }}>
          <input class={inputClass} value={code} maxLength={2} placeholder={t('country.code')} aria-label={t('country.code')}
            onInput={(e) => setCode((e.currentTarget as HTMLInputElement).value)} />
        </form>
      </div>
    </div>
  )
}
