/// <reference types="vite/client" />
import type { Host, Live, PluginModule } from '@splify2/plugin-api'
import { events, sites, type Status } from './model'
import './style.css'

const me = (l: Live) => (l.status?.plugins as { id: string; state: string }[] | undefined)?.find((p) => p.id === 'recheck')

/* Последний ответ status — для строки свёрнутой карточки (summary синхронный). */
let last: Status | null = null

function Screen({ host }: { host: Host }) {
  const { useEffect, useState } = host.preact.hooks
  const { Card, CardContent, CardHead, KV, Badge, DangerButton, StateLine } = host.ui
  const t = host.i18n.t
  const [st, setSt] = useState<Status | null>(last)
  const [err, setErr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let alive = true
    const load = () => host.rpc.call<Status>('status').then((s) => { last = s; if (alive) { setSt(s); setErr(null) } },
      (e: Error) => { if (alive) setErr(e.message) })
    void load()
    /* Служба шлёт ядру state при каждой записи состояния, ядро — событие plugin-state панели; опрос — запас. */
    const off = [host.core.on('plugin-state', (e) => { if (!e.id || e.id === 'recheck') void load() }),
                 host.core.on('plugin', () => void load())]
    const tm = setInterval(load, 10000)
    return () => { alive = false; clearInterval(tm); off.forEach((d) => d()) }
  }, [])

  const forget = async () => {
    if (!(await host.confirm({ title: t('forget.confirm'), body: t('forget.body'), confirmLabel: t('forget.go'), tone: 'destructive' }))) return
    setBusy(true)
    try { await host.rpc.call('forget'); host.notify(t('forget.done'), 'ok'); setSt(await host.rpc.call<Status>('status')) }
    catch (e) { host.notify((e as Error).message, 'error') }
    finally { setBusy(false) }
  }

  if (!st) return <p class="recheck-ui__muted">{err ?? t('loading')}</p>
  const list = sites(st.state)
  const evs = events(st.events).slice(0, 12)
  return (
    <div class="recheck-ui">
      <Card><CardContent>
        <CardHead title={t('status.title')} />
        <StateLine ok={st.running}>{st.running ? t('status.running') : st.strict ? t('status.stopped_strict') : t('status.stopped')}</StateLine>
        <KV k={t('status.wan')} v={st.wan_dev ? `${st.wan} · ${st.wan_dev}` : t('status.no_wan')} />
        <KV k={t('status.mode')} v={st.strict ? t('status.strict') : t('status.failopen')} />
        <KV k={t('status.traffic')} v={t('status.traffic_v', { queued: st.queued, watched: st.watched })} />
      </CardContent></Card>
      <Card><CardContent>
        <CardHead title={t('learn.title')} />
        <KV k={t('learn.sites')} v={t('learn.sites_v', { confirmed: st.confirmed, learned: st.learned })} />
        <KV k={t('learn.memory')} v={st.persist ? t('learn.flash') : t('learn.ram')} />
        {list.length ? (
          <ul class="recheck-ui__list">
            {list.slice(0, 50).map((s) => (
              <li key={`${s.ip}:${s.port}`}>
                <span>{s.host || s.ip}</span>
                <span class="recheck-ui__muted">{s.proto} {s.port}</span>
                <Badge variant={s.confirmed ? 'default' : 'outline'}>{s.confirmed ? t('learn.confirmed') : t('learn.trying')}</Badge>
              </li>
            ))}
          </ul>
        ) : <p class="recheck-ui__muted">{t('learn.empty')}</p>}
        {evs.length > 0 && (
          <>
            <h4>{t('events.title')}</h4>
            <ul class="recheck-ui__list">
              {evs.map((e, i) => (
                <li key={i}><span>{t(`ev.${e.what}`) === `ev.${e.what}` ? e.what : t(`ev.${e.what}`)}</span><span>{e.host || e.ip}</span></li>
              ))}
            </ul>
          </>
        )}
        <DangerButton onClick={forget} disabled={busy || !st.running} label={t('forget.go')} />
      </CardContent></Card>
    </div>
  )
}

const plugin: PluginModule = {
  activate(host) {
    const t = host.i18n.t
    host.slots.pluginSettings({
      summary: (l) => {
        const p = me(l)
        if (p && p.state !== 'enabled') return { text: t('summary.off'), tone: 'idle' }
        if (!last) return null
        if (!last.running) return { text: t('summary.stopped'), tone: last.strict ? 'bad' : 'warn' }
        return { text: t('summary.ok', { n: last.confirmed }), tone: 'ok' }
      },
      render: () => <Screen host={host} />,
    })
  },
}

export default plugin
