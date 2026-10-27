import type { Host, OutputV2, PluginSettingsContext, SpecV2 } from '@splify2/plugin-api'
import { useState } from 'preact/hooks'
import { Controls } from './controls'
import { Scan } from './scan'
import { DEFAULTS, freeName, hostPort, nameOk, newOutput, patchOutput, tunnelCount, warpOutputs, type Defaults, type WarpStatus } from './model'
import { Cloud } from './icons'

interface Props {
  host: Host
  ctx: PluginSettingsContext
  defaults: Defaults
  reloadDefaults: () => Promise<void>
}

/** Раскрытая карточка плагина: выходы WARP со всем, что к ним относится, и настройки для новых выходов. */
export function WarpSettings({ host, ctx, defaults, reloadDefaults }: Props) {
  const { Button } = host.ui
  const t = host.i18n.t
  const live = host.core.useLive()
  const { spec } = host.core.useSpec()
  if (!spec) return <div class="warpbox-ui__note">{t('loading')}</div>
  const outs = warpOutputs(spec)
  return (
    <div class="warpbox-ui">
      {outs.map(([name, o]) => <Group key={name} host={host} spec={spec} name={name} o={o} live={ctx.live ?? live} />)}
      <Create host={host} spec={spec} defaults={defaults} first={outs.length === 0} />
      <Defaults_ host={host} current={defaults} reload={reloadDefaults} />
      <div class="warpbox-ui__row"><Button variant="ghost" onClick={ctx.close}>{t('close')}</Button></div>
    </div>
  )
}

function Create({ host, spec, defaults, first }: { host: Host; spec: SpecV2; defaults: Defaults; first: boolean }) {
  const { Button, inputClass } = host.ui
  const t = host.i18n.t
  const [open, setOpen] = useState(first)
  const [name, setName] = useState(() => freeName(spec.outputs))
  const taken = !!spec.outputs?.[name]
  const ok = nameOk(name) && !taken
  const add = (e: Event) => {
    e.preventDefault()
    if (!ok) return
    void host.core.edit((d) => { d.outputs = d.outputs ?? {}; if (!d.outputs[name]) d.outputs[name] = newOutput(defaults) })
    setOpen(false)
  }
  if (!open) {
    return (
      <button type="button" class="warpbox-ui__add" onClick={() => { setName(freeName(spec.outputs)); setOpen(true) }}>
        + {t('output.add')}
      </button>
    )
  }
  return (
    <form class="warpbox-ui__tile" onSubmit={add}>
      <div class="warpbox-ui__hero">
        <Cloud />
        <div>
          <div class="warpbox-ui__tile-title">{t('output.newTitle')}</div>
          <div class="warpbox-ui__note">{t('output.newNote')}</div>
        </div>
      </div>
      <div class="warpbox-ui__row">
        <input class={inputClass} value={name} spellcheck={false} aria-label={t('output.name')}
          onInput={(e) => setName((e.currentTarget as HTMLInputElement).value.toLowerCase())} />
        <Button type="submit" disabled={!ok}>{t('output.create')}</Button>
        {!first && <Button variant="ghost" onClick={() => setOpen(false)}>{t('output.cancel')}</Button>}
      </div>
      {!ok && name && <div class="warpbox-ui__note">{taken ? t('output.nameTaken') : t('output.nameBad')}</div>}
    </form>
  )
}

function Group({ host, spec, name, o, live }: { host: Host; spec: SpecV2; name: string; o: OutputV2; live: ReturnType<Host['core']['getLive']> }) {
  const { Button, Flag, Badge } = host.ui
  const t = host.i18n.t
  const count = tunnelCount(o.count)
  const st = live.status?.outputs?.[name]
  const g = st?.group
  const wst = (g as { warp?: WarpStatus } | undefined)?.warp
  const selected = g?.selected ?? null
  const alive = new Set(g?.alive ?? [])
  const applied = (g?.members as string[] | undefined) ?? []
  const used = (spec.rules ?? []).filter((r) => r.out === name).length
  /* Туннель регистрируется до минуты (ключи, подбор точки): пока не все готовы — не поломка, а ход настройки. */
  const settling = !!st && applied.length < count
  const gx = g as { why?: string; tolerance?: number } | undefined
  const hold = gx?.why === 'in_tolerance' && selected ? t('head.hold', { ms: gx.tolerance ?? 50 }) : ''
  const head = !st ? t('head.notApplied')
    : selected ? `${t('head.working', { tunnel: selected })}${hold}${settling ? t('head.preparing') : ''}`
    : settling ? t('head.registering')
    : t('head.down')
  const changing = st && applied.length && applied.length !== count ? t('head.applying', { count, was: applied.length }) : ''
  const set = (patch: Record<string, unknown>) => void host.core.edit((d) => { patchOutput(d, name, patch) })

  const remove = async () => {
    const yes = await host.confirm({ title: t('output.deleteTitle', { name }), body: t('output.deleteBody'), tone: 'destructive' })
    if (!yes) return
    void host.core.edit((d) => { if (d.outputs) delete d.outputs[name] })
  }
  const members = Array.from({ length: count }, (_, i) => `${name}.${i + 1}`)
  return (
    <section class="warpbox-ui__group">
      <header class="warpbox-ui__head">
        <span class="warpbox-ui__dot" data-state={!st || (!selected && settling) ? 'wait' : selected ? 'ok' : 'bad'} aria-hidden="true" />
        <div class="warpbox-ui__grow">
          <h3>{name} {o.transport === 'masque' && <Badge variant="proto">MASQUE</Badge>}</h3>
          <div class="warpbox-ui__note">{head}{changing}{used ? t('head.rules', { n: used }) : ''}</div>
        </div>
        <Button variant="ghost" size="sm" disabled={used > 0} title={used ? t('output.deleteBusy') : undefined} onClick={remove}>
          {t('output.delete')}
        </Button>
      </header>
      {wst?.why && <div class="warpbox-ui__error">{wst.why}</div>}
      <div class="warpbox-ui__tile">
        <div class="warpbox-ui__tile-title">{t('tunnels')}</div>
        <div class="warpbox-ui__pills">
          {members.map((m) => {
            const ws = wst?.members?.find((x) => x.out === m)
            const ready = applied.includes(m)
            const state = !st ? 'wait' : alive.has(m) ? 'ok' : ready ? 'bad' : 'wait'
            const lat = (g as { latency?: Record<string, number> } | undefined)?.latency?.[m]
            const ep = ws?.ip ? hostPort(ws.ip, ws.port) : null
            return (
              <div key={m} class="warpbox-ui__pill" data-on={m === selected ? '1' : '0'} title={m === selected ? t('tunnel.carries') : undefined}>
                <span class="warpbox-ui__pill-top">
                  <span class="warpbox-ui__dot" data-state={state} aria-hidden="true" />
                  <span class="warpbox-ui__grow">{m}</span>
                  <span class="warpbox-ui__note">{typeof lat === 'number' ? `${lat} мс` : ''}</span>
                </span>
                <span class="warpbox-ui__note">
                  {ws?.seen && <Flag cc={ws.seen} />} {ws?.colo ?? ''}{' '}
                  <span class="warpbox-ui__mono">{ep ?? (!st ? '' : !ready ? t('tunnel.waiting') : t('tunnel.registering'))}</span>
                </span>
              </div>
            )
          })}
        </div>
      </div>
      <Controls host={host} o={o} set={set} />
      <div class="warpbox-ui__tile">
        <div class="warpbox-ui__tile-title">{t('points.title')}</div>
        <Scan host={host} group={name} applied={!!st} />
      </div>
    </section>
  )
}

/** Настройки плагина «для новых выходов»: хранит хост (схема settings.schema.json), читают и пишут методы плагина. */
function Defaults_({ host, current, reload }: { host: Host; current: Defaults; reload: () => Promise<void> }) {
  const { Segmented, Button, FieldRow, inputClass } = host.ui
  const t = host.i18n.t
  const [d, setD] = useState<Defaults>({ ...DEFAULTS, ...current })
  const [saved, setSaved] = useState(false)
  const put = (patch: Partial<Defaults>) => { setSaved(false); setD({ ...d, ...patch }) }
  const save = () =>
    host.rpc.call('defaults_set', { transport: d.transport, count: String(d.count), pick: d.pick, exclude_countries: d.exclude_countries.replace(/\s+/g, '') })
      .then(() => reload()).then(() => setSaved(true), (e: Error) => host.notify(e.message, 'error'))
  return (
    <div class="warpbox-ui__tile">
      <div class="warpbox-ui__tile-title">{t('defaults.title')}</div>
      <Segmented label={t('transport.title')} value={d.transport}
        items={[{ value: 'awg', label: 'AmneziaWG' }, { value: 'masque', label: 'MASQUE' }]} onChange={(v) => put({ transport: v })} />
      <Segmented label={t('count.title')} value={String(Math.min(d.count, 5))}
        items={[1, 2, 3, 4, 5].map((n) => ({ value: String(n), label: String(n) }))} onChange={(v) => put({ count: Number(v) })} />
      <Segmented label={t('pick.title')} value={d.pick}
        items={[{ value: 'latency', label: t('pick.latency') }, { value: 'order', label: t('pick.order') }]} onChange={(v) => put({ pick: v })} />
      <FieldRow label={t('defaults.countries')} caption={t('defaults.countriesHint')}>
        <input class={inputClass} value={d.exclude_countries} maxLength={40} spellcheck={false}
          onInput={(e) => put({ exclude_countries: (e.currentTarget as HTMLInputElement).value.toUpperCase() })} />
      </FieldRow>
      <div class="warpbox-ui__row">
        <Button onClick={save}>{t('defaults.save')}</Button>
        {saved && <span class="warpbox-ui__note">{t('defaults.saved')}</span>}
      </div>
    </div>
  )
}
