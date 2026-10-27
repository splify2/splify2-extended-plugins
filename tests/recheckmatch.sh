#!/bin/sh
# Стенд плагина recheck: служба под настоящим демоном steer (супервизор), слот nft, настройки, методы rpc.
#
#   STEER=<steer>  PLUGIN_SDK=<plugin-sdk>  sh tests/recheckmatch.sh
#
# Движок заменён заглушкой (она пишет свои аргументы и событие ready), а netifd — заглушками ubus и jsonfilter: стенд
# проверяет то, что делает плагин вокруг движка, а не сам движок (его стенды — в репозитории recheck, `make netns-test`).
#
#   1  s2p lint --official; compat со стороной ядра steer (tests/compat/run.sh --steer) и splify2;
#   2  набор правил steer с плагином печатается и принимается настоящим nft (-c): слоты postrouting-post,
#      forward, input и output-raw, очереди и метки — выданные ядром;
#   3  демон запускает службу; hello, ready; движок получил выданные очереди и метки, WAN из netifd, настройки;
#   4  правка настроек перезапускает движок с новыми аргументами; strict — флаг --strict; пределы меньше 16 — нет;
#   5  метод status отвечает по файлу состояния службы; метод forget стирает память и перезапускает движок.
# Под root стенд уходит в своё сетевое пространство; без root — nft -c через unshare -rn, если он доступен.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PLUGIN="$REPO/plugins/recheck"
SDK="${PLUGIN_SDK:-$REPO/../../splicicd/plugin-sdk}"
SDK="$(cd "$SDK" && pwd)"
BIN="${STEER:?нужен STEER — собранный steer ядра 2.1 с службами плагинов}"
BIN="$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")"
S2P="$SDK/bin/s2p"
[ -x "$BIN" ] && [ -x "$S2P" ] || { echo "recheckmatch: нет $BIN или $S2P"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "recheckmatch: python3 нет — пропускаю"; exit 0; }
if [ "${RECHECKMATCH_INNER:-}" != 1 ] && [ "$(id -u)" = 0 ] && unshare -n true 2>/dev/null; then
    RECHECKMATCH_INNER=1 exec unshare -n sh "$0" "$@"
fi
[ "${RECHECKMATCH_INNER:-}" = 1 ] && ip link set lo up 2>/dev/null

tmp="$(mktemp -d)"
D=""
trap 'kill $D 2>/dev/null; wait $D 2>/dev/null; rm -rf "$tmp"' EXIT
pass=0 fail=0
check() {
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
        fail=$((fail + 1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
    fi
}
has() {
    case "$2" in *"$3"*) pass=$((pass + 1)) ;; *)
        fail=$((fail + 1)); printf 'FAIL %s\n  нет подстроки: %s\n  в тексте: %s\n' "$1" "$3" "$2" ;; esac
}
hasnt() {
    case "$2" in *"$3"*)
        fail=$((fail + 1)); printf 'FAIL %s\n  лишняя подстрока: %s\n  в тексте: %s\n' "$1" "$3" "$2" ;; *) pass=$((pass + 1)) ;; esac
}
wait_for() {
    i=0
    while [ $i -lt $(($2 * 10)) ]; do eval "$1" && return 0; sleep 0.1; i=$((i + 1)); done
    eval "$1" && return 0
    return 1
}

# ================= 1. lint и совместимость =============================================================
out="$("$S2P" lint --official "$PLUGIN" 2>&1)"; check "s2p lint --official: чисто" "0" "$?"
has "  без предупреждений" "$out" "ok (предупреждений 0)"
out="$(sh "$SDK/tests/compat/run.sh" --steer "$PLUGIN" 2>&1)"; check "compat со стороной ядра steer (служба: hello, SIGTERM)" "0" "$?"
out="$(sh "$SDK/tests/compat/run.sh" "$PLUGIN" 2>&1)"; check "compat с splify2-api (настройки, граница API)" "0" "$?"

# ================= каталог плагинов стенда, заглушки ===================================================
ROOT="$tmp/plugins" ETC="$tmp/etc" ST="$tmp/st" SB="$tmp/sandbox"
mkdir -p "$ROOT" "$ETC" "$ST" "$SB" "$tmp/stub" "$tmp/sysnet/wan0" "$tmp/sysmod/nf_conntrack_netlink"
cp -r "$PLUGIN" "$ROOT/recheck"
echo 7 > "$tmp/sysnet/wan0/ifindex"
# Движок-заглушка: аргументы — в журнал, событие ready — в стандартный вывод, гаснет по SIGTERM; память пишет при выходе.
cat > "$ROOT/recheck/bin/steer-dpi-live" <<H
#!/bin/sh
echo "\$*" >> "$tmp/engine.log"
state=""; prev=""
for a in "\$@"; do [ "\$prev" = --state ] && state="\$a"; prev="\$a"; done
[ -n "\$state" ] && [ ! -e "\$state" ] && printf 'DPI8 %s\nE 1 1 4 6 443 1 0 1.2.3.4 example.org 0\nE 1 0 4 6 443 1 0 5.6.7.8 other.org 0\n' "\$(wc -l < "$tmp/engine.log")" > "\$state"
echo "event=ready queue=0 fixed_bytes=1"
echo "event=confirmed ms=1 host=example.org ip=1.2.3.4 port=443 recipe=3"
trap 'exit 0' TERM
while :; do sleep 0.1; done
H
chmod +x "$ROOT/recheck/bin/steer-dpi-live"
# jsonfilter и ubus: на роутере их даёт OpenWrt.
cat > "$tmp/stub/jsonfilter" <<'P'
#!/usr/bin/env python3
import json, sys
a = sys.argv[1:]; src = None; exprs = []
while a:
    x = a.pop(0)
    if x == "-i": src = open(a.pop(0)).read()
    elif x == "-s": src = a.pop(0)
    elif x == "-e": exprs.append(a.pop(0))
if src is None: src = sys.stdin.read()
try: d = json.loads(src)
except ValueError: sys.exit(1)
rc = 1
for e in exprs:
    v = d
    for k in e[2:].split("."):
        v = v.get(k) if isinstance(v, dict) else None
    if v is None: continue
    rc = 0
    print("true" if v is True else "false" if v is False else v)
sys.exit(rc)
P
cat > "$tmp/stub/ubus" <<'U'
#!/bin/sh
[ "$1" = listen ] && exit 0
[ "$1" = -t ] && shift 2
[ "$1" = call ] && [ "$2" = network.interface.wan ] && { echo '{"up":true,"l3_device":"wan0"}'; exit 0; }
exit 1
U
chmod +x "$tmp/stub/jsonfilter" "$tmp/stub/ubus"
PATH="$tmp/stub:$PATH"; export PATH
RECHECK_SYS_MODULE="$tmp/sysmod" RECHECK_NFACCT="$tmp/acct" RECHECK_SYS_NET="$tmp/sysnet" RECHECK_TICK=1
export RECHECK_SYS_MODULE RECHECK_NFACCT RECHECK_SYS_NET RECHECK_TICK
STEER_PLUGINS_ROOT="$ROOT"; STEER_PLUGINS_ETC="$ETC"; export STEER_PLUGINS_ROOT STEER_PLUGINS_ETC
CONFD="$ETC/conf/recheck"

# ================= 2. набор правил с плагином ==========================================================
printf 'version: 2\noutputs:\n  d: { kind: direct }\nrules: []\n' > "$tmp/spec.yaml"
rs="$("$BIN" apply --dry-run --spec "$tmp/spec.yaml" 2>&1)"
Q0="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["outputs"]["plugin:recheck"]["queues"][0])' "$ETC/alloc.json" 2>/dev/null)"
Q1="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["outputs"]["plugin:recheck"]["queues"][1])' "$ETC/alloc.json" 2>/dev/null)"
case "$Q0$Q1" in ''|*[!0-9]*) fail=$((fail + 1)); echo "FAIL очереди плагина не выданы: $Q0 $Q1" ;; esac
has "правила: слоты postrouting-post, forward, input, output-raw" "$rs" "jump plugin_recheck_output-raw"
has "  очередь первых пакетов — выданная" "$rs" "counter queue flags bypass to $Q0"
has "  очередь наблюдения — выданная" "$rs" "queue flags bypass to $Q1"
has "  по WAN steer (набор wan_dev)" "$rs" "oifname @wan_dev"
has "  ответы из WAN в сеть (слот forward)" "$rs" "iifname @wan_dev oifname @lan_dev"
has "  свои пакеты движка снимаются с conntrack до него" "$rs" "notrack"
if command -v unshare >/dev/null 2>&1 && command -v nft >/dev/null 2>&1 && unshare -rn true 2>/dev/null; then
    printf '%s\n' "$rs" > "$tmp/rules.nft"
    nout="$(unshare -rn nft -c -f "$tmp/rules.nft" 2>&1)"
    check "набор правил steer с recheck принимает настоящий nft (-c)" "" "$nout"
else
    echo "nft -c недоступен — проверка набора пропущена"
fi

# ================= 3. служба под демоном ===============================================================
"$BIN" daemon --supervise --allow-uid "$(id -u)" --socket "$tmp/s.sock" --spec "$tmp/spec.yaml" --state-dir "$ST" \
    --dnsd-flag --listen-port --dnsd-flag 15531 --dnsd-flag --upstream-port --dnsd-flag 15595 \
    >"$tmp/d.out" 2>"$tmp/d.err" &
D=$!
wait_for '[ -S "$tmp/s.sock" ]' 5
wctl() { "$BIN" ctl --socket "$tmp/s.sock" "$@"; }
hf() { wctl helper "$1" | python3 -c 'import json,sys
d=json.loads(json.load(sys.stdin)["stdout"]); print(d.get(sys.argv[1], "-"))' "$2" 2>&1; }
wait_for '[ "$(hf recheck up)" = True ]' 15
check "служба принята демоном: up (ready)" "True" "$(hf recheck up)"
check "  плагин recheck" "recheck" "$(hf recheck plugin)"
wait_for 'grep -q . "$tmp/engine.log" 2>/dev/null' 5
eng="$(tail -1 "$tmp/engine.log" 2>/dev/null)"
has "движок: очередь — выданная" "$eng" "--queue $Q0 "
has "  очередь наблюдения" "$eng" "--watch-queue $Q1 "
has "  метка своих пакетов и метка проб — разные биты ядра" "$eng" "--skip-mark 0x"
has "  WAN — устройство от netifd" "$eng" "--interface wan0"
has "  память — в рабочем каталоге (flash не трогаем без persist)" "$eng" "--state $ST/plugin/recheck/cache.state"
has "  движок учится" "$eng" "--learn"
hasnt "  без strict по умолчанию" "$eng" "--strict"
STF="$ST/plugin/recheck/recheck.status.json"
wait_for '[ -s "$STF" ]' 5
check "файл состояния: сайтов изучено" "2" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["learned"])' "$STF" 2>&1)"
check "  из них подтверждено" "1" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["confirmed"])' "$STF" 2>&1)"
check "  устройство WAN" "wan0" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["wan_dev"])' "$STF" 2>&1)"
check "  очередь" "$Q0" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["queue"])' "$STF" 2>&1)"
check "  путь движка записан (файл пути)" "1" "$(grep -c '^[0-9]* wan0$' "$ST/plugin/recheck/$Q0.path")"
starts() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["starts"])' "$STF" 2>/dev/null; }
check "  запусков движка — один" "1" "$(starts)"

# ================= 4. настройки ========================================================================
mkdir -p "$CONFD"
cat > "$CONFD/settings.json.new" <<'J'
{"strict": true, "persist": true, "cache_limit": 8, "family_limit": 64, "probe_resources": "https://a.example/file https://b.example/x", "watch_active": true}
J
mv "$CONFD/settings.json.new" "$CONFD/settings.json"
wait_for '[ "$(starts)" = 2 ]' 15
check "правка настроек: движок перезапущен" "2" "$(starts)"
eng="$(tail -1 "$tmp/engine.log")"
has "  strict — флаг движка" "$eng" "--strict"
has "  persist: память на флеше (каталог настроек)" "$eng" "--state $CONFD/cache.state"
has "  предел 64 передан" "$eng" "--family-limit 64"
hasnt "  предел меньше 16 не передан" "$eng" "--cache-limit"
has "  адреса проверки" "$eng" "--probe-resource https://a.example/file --probe-resource https://b.example/x"
has "  проверка загрузок" "$eng" "--watch-active"

# ================= 5. методы rpc =======================================================================
export SPLIFY2_LIB="$SDK/tests/compat/splify2-1.0/lib.sh" SPLIFY2_HOST="$SDK/tests/compat/splify2-1.0/host" S2_SANDBOX="$SB"
export STEER_PLUGIN_ID=recheck STEER_PLUGIN_DIR="$PLUGIN" STEER_PLUGIN_CONF="$CONFD" STEER_PLUGIN_STATE="$ST/plugin/recheck"
st="$(echo '{}' | sh "$PLUGIN/rpc/recheck" status 2>&1)"
has "status: служба работает" "$st" '"running":true'
has "  версия плагина" "$st" '"version"'
has "  очередь" "$st" "\"queue\":$Q0"
has "  изучено сайтов" "$st" '"learned":2'
has "  память движка отдана как есть" "$st" 'DPI8 '
has "  события движка" "$st" 'event=confirmed'
hdr() { echo '{}' | sh "$PLUGIN/rpc/recheck" status 2>&1 | sed -n 's/.*"state":"\(DPI8 [0-9]*\).*/\1/p'; }
H1="$(hdr)"
fo="$(echo '{}' | sh "$PLUGIN/rpc/recheck" forget 2>&1)"
has "forget: ответ ok" "$fo" '"ok":true'
wait_for '[ "$(starts)" = 3 ]' 15
check "  движок перезапущен" "3" "$(starts)"
H2="$(hdr)"
check "  память стёрта: движок начал с чистого файла (заголовок новый)" "1" "$([ -n "$H1" ] && [ -n "$H2" ] && [ "$H1" != "$H2" ] && echo 1 || echo 0)"

# Служба остановлена сигналом: демон поднимает её заново (с паузой перезапуска).
OLD="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "$STF")"
kill "$OLD"
newpid() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "$STF" 2>/dev/null; }
wait_for '[ -n "$(newpid)" ] && [ "$(newpid)" != "$OLD" ]' 20
check "служба остановлена сигналом — демон поднял её снова" "1" "$([ -n "$(newpid)" ] && [ "$(newpid)" != "$OLD" ] && echo 1 || echo 0)"
check "  движок после перезапуска службы — тот же набор настроек (strict)" "1" "$(tail -1 "$tmp/engine.log" | grep -c -- '--strict')"

printf '\n%d проверок пройдено' "$pass"
if [ "$fail" -gt 0 ]; then printf ', %d ПРОВАЛЕНО\n' "$fail"; exit 1; fi
printf '\nвсе проверки прошли\n'
