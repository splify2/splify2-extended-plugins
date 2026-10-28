#!/usr/bin/env python3
"""Строгий режим recheck на настоящем NFQUEUE ядра Linux, в своих сетевых пространствах (sudo -n unshare).

Правила — строки самого файла plugins/recheck/nft/recheck.nft (слоты postrouting-post и forward) с подстановками,
как их делает ядро steer; наборы @lan_dev и @wan_dev — устройства стенда. Сеть: клиент (192.168.50.2) — роутер —
«интернет» (198.51.100.2); клиент шлёт UDP.

  1. строгий режим выключен, движка нет — пакеты проходят (очередь с bypass);
  2. строгий режим включён (WAN в @p_recheck_strict), движка нет — ядро роняет пакеты: мимо обхода не проходит ничего;
  3. строгий режим включён, очередь слушают (RECHECK_NFQ_BENCH — build/nfq-bench из репозитория recheck) — проходят;
  4. запросы клиента встали в очередь, а ответы из WAN — тоже (слот forward) — по счётчикам правил.

Хост не меняется: всё — в пространствах, которые исчезают с процессом.
"""
import json, os, re, socket, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
NFT = HERE.parent / 'plugins' / 'recheck' / 'nft' / 'recheck.nft'
Q0, Q1, M0, M1, SM = 4100, 4101, 0x01000000, 0x02000000, 0x000000ff

def sh(*a, **k):
    return subprocess.run(list(a), check=True, text=True, capture_output=True, **k).stdout

def render():
    text = NFT.read_text()
    subst = {'queue0': str(Q0), 'queue1': str(Q1), 'mark0': hex(M0), 'mark1': hex(M1), 'steer_mask': hex(SM)}
    text = re.sub(r'\{(queue0|queue1|mark0|mark1|steer_mask)\}', lambda m: subst[m.group(1)], text)
    text = re.sub(r'@(strict|private4|private6)\b', r'@p_recheck_\1', text)
    text = re.sub(r'^set (\w+)', r'set p_recheck_\1', text, flags=re.M)
    hooks = {'output-raw': 'type filter hook output priority -300;', 'postrouting-post': 'type filter hook postrouting priority 100;',
             'forward': 'type filter hook forward priority 0;', 'input': 'type filter hook input priority 0;'}
    text = '\n'.join(l for l in text.splitlines() if not l.startswith('#'))
    text = re.sub(r'chain ([\w-]+) \{', lambda m: 'chain %s {\n  %s policy accept;' % (m.group(1), hooks[m.group(1)]), text)
    return ('table inet steer {\n set lan_dev { type ifname; elements = { "lan0" }; }\n'
            ' set wan_dev { type ifname; elements = { "wan0" }; }\n' + text + '\n}\n')

def ns():
    p = subprocess.Popen(['unshare', '-n', 'sleep', '120'])
    time.sleep(0.1)
    return p

def nse(p, *a, **k):
    return sh('nsenter', '-t', str(p.pid), '-n', *a, **k)

def send(lan, n):
    code = ('import socket\ns=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)\n'
            'for i in range(%d): s.sendto(b"x"*64,("198.51.100.2",9000))\n' % n)
    nse(lan, sys.executable, '-I', '-c', code)

def received(wan, n, count):
    code = ('import socket,sys\ns=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)\ns.bind(("0.0.0.0",9000))\n'
            's.settimeout(1.0)\nn=0\ntry:\n while n<%d:\n  s.recv(2048); n+=1\nexcept OSError: pass\nprint(n)\n' % count)
    return subprocess.Popen(['nsenter', '-t', str(wan.pid), '-n', sys.executable, '-I', '-c', code], stdout=subprocess.PIPE, text=True)

def counters():
    js = json.loads(sh('nft', '-j', 'list', 'ruleset'))
    out = {}
    for x in js['nftables']:
        r = x.get('rule')
        if not r: continue
        pk = sum(e['counter']['packets'] for e in r['expr'] if 'counter' in e)
        q = [e['queue'] for e in r['expr'] if 'queue' in e]
        if q:
            k = (r['chain'], q[0]['num'], 'bypass' in str(q[0].get('flags', '')))
            out[k] = out.get(k, 0) + pk
    return out

def inside():
    fail = 0
    def check(name, want, got):
        nonlocal fail
        ok = want == got
        fail += not ok
        print(('ok   ' if ok else 'FAIL ') + name + ('' if ok else '  ожидалось %r, вышло %r' % (want, got)))
    sh('ip', 'link', 'set', 'lo', 'up')
    lan, wan = ns(), ns()
    try:
        sh('ip', 'link', 'add', 'lan0', 'type', 'veth', 'peer', 'name', 'lanc')
        sh('ip', 'link', 'add', 'wan0', 'type', 'veth', 'peer', 'name', 'wanc')
        sh('ip', 'link', 'set', 'lanc', 'netns', str(lan.pid))
        sh('ip', 'link', 'set', 'wanc', 'netns', str(wan.pid))
        sh('ip', 'addr', 'add', '192.168.50.1/24', 'dev', 'lan0'); sh('ip', 'link', 'set', 'lan0', 'up')
        sh('ip', 'addr', 'add', '198.51.100.1/24', 'dev', 'wan0'); sh('ip', 'link', 'set', 'wan0', 'up')
        sh('sysctl', '-qw', 'net.ipv4.ip_forward=1')
        for p, dev, a, gw in ((lan, 'lanc', '192.168.50.2/24', '192.168.50.1'), (wan, 'wanc', '198.51.100.2/24', '198.51.100.1')):
            nse(p, 'ip', 'link', 'set', 'lo', 'up'); nse(p, 'ip', 'addr', 'add', a, 'dev', dev)
            nse(p, 'ip', 'link', 'set', dev, 'up'); nse(p, 'ip', 'route', 'add', 'default', 'via', gw)
        try: sh('sysctl', '-qw', 'net.netfilter.nf_conntrack_acct=1')
        except subprocess.CalledProcessError: pass
        sh('nft', '-f', '-', input=render())
        time.sleep(0.3)

        # 1. без строгого режима, движка нет
        r = received(wan, 1, 5); time.sleep(0.2); send(lan, 5)
        check('1. строгий выключен, движка нет — пакеты проходят', '5', r.communicate(timeout=10)[0].strip())
        c = counters()
        check('   прошли через очередь первых пакетов с bypass', True, c.get(('postrouting-post', Q0, True), 0) >= 5)

        # 2. строгий режим, движка нет — новый поток (другой порт источника у нового сокета)
        sh('nft', 'add', 'element', 'inet', 'steer', 'p_recheck_strict', '{ "wan0" }')
        r = received(wan, 1, 5); time.sleep(0.2); send(lan, 5)
        check('2. строгий включён, движка нет — ничего не прошло', '0', r.communicate(timeout=10)[0].strip())
        c = counters()
        check('   пакеты встали в очередь без bypass', True, c.get(('postrouting-post', Q0, False), 0) >= 5)

        # 3. строгий режим, очередь слушают
        bench = os.environ.get('RECHECK_NFQ_BENCH', '')
        if bench and os.access(bench, os.X_OK):
            q = subprocess.Popen([bench, 'queue', str(Q0), '1024'], stdout=subprocess.PIPE, text=True)
            check('   слушатель очереди поднялся', 'ready', q.stdout.readline().strip())
            r = received(wan, 1, 5); time.sleep(0.2); send(lan, 5)
            check('3. строгий включён, движок слушает — пакеты проходят', '5', r.communicate(timeout=10)[0].strip())
            seen = json.loads(q.communicate(timeout=15)[0].strip().splitlines()[-1])['queue_seen']
            check('   все прошли через слушателя', True, seen >= 5)
        else:
            print('skip 3. нет RECHECK_NFQ_BENCH (build/nfq-bench репозитория recheck)')

        # 4. выключение строгого режима — снова bypass
        sh('nft', 'flush', 'set', 'inet', 'steer', 'p_recheck_strict')
        r = received(wan, 1, 5); time.sleep(0.2); send(lan, 5)
        check('4. строгий снят — снова проходят', '5', r.communicate(timeout=10)[0].strip())
    finally:
        lan.kill(); wan.kill()
    print('recheck_strict_netns: %s' % ('все проверки прошли' if not fail else 'провалено %d' % fail))
    return 1 if fail else 0

if __name__ == '__main__':
    if '--inside' in sys.argv:
        sys.exit(inside())
    if subprocess.run(['sudo', '-n', 'true'], capture_output=True).returncode != 0 and os.geteuid() != 0:
        print('recheck_strict_netns: нужен root или sudo -n — пропускаю'); sys.exit(0)
    pre = [] if os.geteuid() == 0 else ['sudo', '-n', 'env', 'RECHECK_NFQ_BENCH=' + os.environ.get('RECHECK_NFQ_BENCH', '')]
    sys.exit(subprocess.run(pre + ['unshare', '-n', sys.executable, '-I', str(Path(__file__).resolve()), '--inside']).returncode)
