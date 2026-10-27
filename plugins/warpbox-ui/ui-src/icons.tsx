import { h } from 'preact'

/** Облако — значок вида WARP (линия, как у остальных значков панели). */
export function Cloud({ className, class: cls }: { className?: string; class?: string }) {
  return h('svg', {
    class: className ?? cls, width: 20, height: 20, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
    'stroke-width': 2, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true',
  }, h('path', { d: 'M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z' }))
}
