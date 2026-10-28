import type { Host } from '@splify2/plugin-api'
import { useEffect, useState } from 'preact/hooks'
import { hostPort, type ScanState } from './model'

/** Подбор точек входа: запуск, ход и таблица найденного. Точки ищет роутер (метод scan), страница только спрашивает. */
export function Scan({ host, group, applied, pinned, pin }: { host: Host; group: string; applied: boolean; pinned: string; pin: (point: string | undefined) => void }) {
  const { Button, Flag } = host.ui
  const t = host.i18n.t
  const [scan, setScan] = useState<ScanState | null>(null)
  const [err, setErr] = useState('')

  const load = () => host.rpc.call<ScanState>('scan_state', { group }).then(setScan, () => undefined)
  useEffect(() => { void load() }, [group])
  /* Идёт подбор — спрашиваем чаще; опрос останавливается вместе с подбором. */
  useEffect(() => {
    if (!scan?.running) return
    const id = setInterval(() => void load(), 3000)
    return () => clearInterval(id)
  }, [scan?.running, group])

  const start = () => {
    setErr('')
    host.rpc.call('scan', { group }).then(
      () => { setScan((s) => ({ running: true, at: s?.at ?? 0, result: null })); void load() },
      (e: Error) => setErr(e.message),
    )
  }
  const res = scan?.result
  const pts = res?.points ?? []
  const masque = res?.transport === 'masque'
  const klass = [t('points.ok'), t('points.busy'), t('points.nohttps')]
  return (
    <div class="warpbox-ui__scan">
      <div class="warpbox-ui__row">
        <Button variant="outline" size="sm" disabled={!applied || !!scan?.running} onClick={start}>
          {scan?.running ? t('points.scanning') : t('points.scan')}
        </Button>
        {!applied && <span class="warpbox-ui__note">{t('points.afterSave')}</span>}
        {res && !scan?.running && (
          <span class="warpbox-ui__note">
            {res.ok !== false ? t('points.found', { n: pts.length }) : res.error}
            {res.filtered ? t('points.filtered', { n: res.filtered }) : ''}
          </span>
        )}
      </div>
      {err && <div class="warpbox-ui__error">{err}</div>}
      {pinned && <div class="warpbox-ui__note">{t('points.pinned', { point: pinned })}</div>}
      {pts.length > 0 && !scan?.running && (
        <div class="warpbox-ui__tablewrap">
          <table class="warpbox-ui__points">
            <thead>
              <tr>
                <th>{t('points.col.point')}</th>
                {!masque && <th>{t('points.col.colo')}</th>}
                <th>{t('points.col.rtt')}</th>
                {!masque && <th>{t('points.col.loss')}</th>}
                <th />
              </tr>
            </thead>
            <tbody>
              {pts.map((p) => (
                <tr key={hostPort(p.ip, p.port)} data-class={masque ? (p.ok ? 0 : 2) : p.class ?? 0}>
                  <td>
                    <div class="warpbox-ui__mono">{hostPort(p.ip, p.port)}</div>
                    <div class="warpbox-ui__note">
                      {masque ? (p.ok ? t('points.ok') : p.error || t('points.noanswer')) : p.class ? klass[p.class] ?? '' : ''}
                    </div>
                  </td>
                  {!masque && <td>{p.cc ? <Flag cc={p.cc} /> : null} {p.colo || '—'}</td>}
                  <td>{typeof p.rtt === 'number' && p.rtt >= 0 ? `${p.rtt} мс` : '—'}</td>
                  {!masque && <td>{p.loss ?? 0}%</td>}
                  <td>
                    {pinned === hostPort(p.ip, p.port)
                      ? <Button variant="ghost" size="sm" onClick={() => pin(undefined)}>{t('points.unpin')}</Button>
                      : <Button variant="ghost" size="sm" disabled={masque ? !p.ok : !!p.class} onClick={() => pin(hostPort(p.ip, p.port))}>{t('points.pin')}</Button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
