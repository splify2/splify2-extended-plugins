/// <reference types="vite/client" />
import type { Live, OutputStatus, OutputV2, PluginModule } from '@splify2/plugin-api'
import { Cloud } from './icons'
import { Controls } from './controls'
import { DEFAULTS, freeName, newOutput, tunnelsUp, type Defaults } from './model'
import { WarpSettings } from './settings'
import './style.css'

/** Туннелей в группе и сколько из них отвечает, по `status`. */
const counts = (st: OutputStatus): [number, number] => {
  const n = (st.group?.members as string[] | undefined)?.length ?? 0
  return [tunnelsUp(n, st)[0], n]
}
const warpStatus = (l: Live): [string, OutputStatus][] => Object.entries(l.status?.outputs ?? {}).filter(([, o]) => o.kind === 'warp')

const plugin: PluginModule = {
  activate(host) {
    const t = host.i18n.t
    const { h } = host.preact

    /* Настройки «для новых выходов» плагин читает заранее и держит: вид выхода создаёт выход сразу, без ожидания. */
    let defaults: Defaults = { ...DEFAULTS }
    const loadDefaults = () => host.rpc.call<Defaults>('defaults_get').then((d) => { defaults = { ...DEFAULTS, ...d } }, () => undefined)
    void loadDefaults()

    host.slots.pluginSettings({
      summary: (l) => {
        const me = (l.status?.plugins as { id: string; state: string }[] | undefined)?.find((p) => p.id === 'warpbox')
        if (me && me.state !== 'enabled') return { text: t('summary.off'), tone: 'idle' }
        const outs = warpStatus(l)
        if (!outs.length) return { text: t('summary.none'), tone: 'idle' }
        let ok = 0, total = 0
        for (const [, o] of outs) { const [u, n] = counts(o); ok += u; total += n }
        if (!total) return { text: t('summary.waiting'), tone: 'idle' }
        return ok ? { text: t('summary.ok', { ok, total }), tone: 'ok' } : { text: t('summary.down'), tone: 'bad' }
      },
      render: (ctx) => <WarpSettings host={host} ctx={ctx} defaults={defaults} reloadDefaults={loadDefaults} />,
    })

    host.slots.outputKind({
      kind: 'warp',
      label: t('kind.label'),
      icon: Cloud,
      create: () => newOutput(defaults),
      /* Выбранный в правиле выход WARP правится на месте: число туннелей, выбор, страна, протокол. */
      editor: (o: OutputV2, set, name) => (
        <Controls
          key={name}
          host={host}
          o={o}
          set={(patch) => {
            const next: OutputV2 = { ...o }
            for (const [k, v] of Object.entries(patch)) { if (v === undefined) delete next[k]; else next[k] = v }
            set(next)
          }}
        />
      ),
      summary: (_o, st) => {
        const [ok, n] = st ? counts(st) : [0, 0]
        return h('span', null, n ? t('tile.tunnels', { ok, total: n }) : t('summary.waiting'))
      },
      ruleTarget: { group: t('target.group') },
      hidesOwned: true,
    })

    host.slots.boardTile({
      id: 'warp',
      order: 500,
      when: (l) => warpStatus(l).length > 0,
      render: (l) => {
        const { Card, CardContent, CardHead, Badge, KV } = host.ui
        return h(Card, null, h(CardContent, null,
          h(CardHead, { title: t('tile.title') }),
          ...warpStatus(l).map(([name, o]) => {
            const [ok, n] = counts(o)
            const sel = o.group?.selected
            return h(KV, {
              key: name,
              k: h('span', null, name, ' ', h(Badge, { variant: 'proto' }, 'WARP')),
              v: n ? `${t('tile.tunnels', { ok, total: n })}${sel ? ` · ${sel}` : ''}` : t('summary.waiting'),
            })
          })))
      },
    })

    host.slots.badge({
      id: 'masque',
      group: 'transport',
      rank: 40,
      match: (o) => (o.kind === 'warp' && o.transport === 'masque' ? { text: t('badge.masque') } : null),
    })

    host.slots.setupVia({
      id: 'warp',
      label: 'WARP',
      caption: t('via.caption'),
      available: async () => {
        try {
          const p = (await host.core.plugins()).find((x) => x.id === 'warpbox')
          return p && p.state !== 'failed' ? true : t('via.missing')
        } catch {
          return true /* не знаем — не значит «нет» */
        }
      },
      render: (done) => {
        const { Button } = host.ui
        const make = () => {
          let name = ''
          void host.core.edit((draft) => {
            draft.outputs = draft.outputs ?? {}
            name = freeName(draft.outputs)
            draft.outputs[name] = newOutput(defaults)
          }).then(() => done([name]))
        }
        return (
          <div class="warpbox-ui__via">
            <p>{t('via.text')}</p>
            <Button onClick={make}>{t('via.go')}</Button>
          </div>
        )
      },
    })
  },
}

export default plugin
