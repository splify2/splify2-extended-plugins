// Стенд чистой логики плагина: node --experimental-strip-types --test tests/model.test.ts
import test from 'node:test'
import assert from 'node:assert/strict'
import { codes, countItems, DEFAULTS, freeName, hostPort, nameOk, newOutput, num, patchOutput, tunnelCount, warpOutputs } from '../ui-src/model'

test('число из спеки: строка читается, мусор — умолчание', () => {
  assert.equal(num('3', 1), 3)
  assert.equal(num('x', 1), 1)
  assert.equal(tunnelCount('0'), 1)
  assert.equal(tunnelCount(2.9), 2)
  assert.equal(tunnelCount(undefined), 1)
})

test('страны: строка и список, регистр, чужое отбрасывается', () => {
  assert.deepEqual(codes('nl'), ['NL'])
  assert.deepEqual(codes(['ru', 5, 'by']), ['RU', 'BY'])
  assert.equal(codes('nld'), undefined)
  assert.equal(codes(undefined), undefined)
})

test('свободное имя: warp, warp2, warp3', () => {
  assert.equal(freeName({}), 'warp')
  assert.equal(freeName({ warp: {} }), 'warp2')
  assert.equal(freeName({ warp: {}, warp2: {} }), 'warp3')
})

test('имя нового выхода: короткое, латиницей', () => {
  assert.ok(nameOk('warp2'))
  assert.ok(!nameOk('Warp'))
  assert.ok(!nameOk('a'.repeat(16)))
  assert.ok(!nameOk('2warp'))
})

test('правка выхода: ключ без значения убирается, остальное цело', () => {
  const spec = { version: 2 as const, outputs: { cf: { kind: 'warp', count: 3, pick: 'order', custom: 1 } } }
  assert.ok(patchOutput(spec, 'cf', { count: undefined, transport: 'masque' }))
  assert.deepEqual(spec.outputs.cf, { kind: 'warp', pick: 'order', custom: 1, transport: 'masque' })
  assert.ok(!patchOutput(spec, 'нет', { count: 2 }))
})

test('выходы WARP спеки', () => {
  const spec = { version: 2 as const, outputs: { d: { kind: 'direct' }, cf: { kind: 'warp' } } }
  assert.deepEqual(warpOutputs(spec).map(([n]) => n), ['cf'])
  assert.deepEqual(warpOutputs(null), [])
})

test('новый выход по настройкам: умолчания ядра не пишутся', () => {
  assert.deepEqual(newOutput(DEFAULTS), { kind: 'warp' })
  assert.deepEqual(newOutput({ transport: 'awg', count: 3, pick: 'order', exclude_countries: 'ru, by,RU' }),
    { kind: 'warp', count: 3, pick: 'order', exclude_countries: ['RU', 'BY'] })
  // У MASQUE страну подбором не сменить — ключ не пишется.
  assert.deepEqual(newOutput({ transport: 'masque', count: 1, pick: 'latency', exclude_countries: 'RU' }), { kind: 'warp', transport: 'masque' })
})

test('кнопки числа туннелей и адрес точки', () => {
  assert.deepEqual(countItems(3).map((i) => i.value), ['1', '2', '3', '4', '5'])
  assert.deepEqual(countItems(8).map((i) => i.value), ['1', '2', '3', '4', '5', '8'])
  assert.equal(hostPort('1.2.3.4', 2408), '1.2.3.4:2408')
  assert.equal(hostPort('2606::1', 443), '[2606::1]:443')
})
