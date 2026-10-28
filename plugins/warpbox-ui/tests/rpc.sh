#!/bin/sh
# Стенд методов плагина (rpc/warpbox, bin/scan-job) на заглушке хоста splify2-api из plugin-sdk: те же службы и ответы,
# что у настоящего хоста, поверх песочницы. Ядро (`steer warp-scan`) подменено программой, которая печатает точки.
#
#   sh tests/rpc.sh            (plugin-sdk — соседний каталог или PLUGIN_SDK=…)
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
SDK="${PLUGIN_SDK:-}"
for c in "$SDK" "$HERE/../../../plugin-sdk" /home/yo1nk/splicicd/plugin-sdk; do
    [ -n "$c" ] && [ -f "$c/tests/compat/splify2-1.0/host" ] && { SDK="$c"; break; }
done
STUB="$SDK/tests/compat/splify2-1.0"
[ -f "$STUB/host" ] || { echo "rpc: заглушки хоста нет (PLUGIN_SDK=…) — ПРОПУСК"; exit 0; }
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"; else fail=$((fail + 1)); printf 'FAIL %s\n  ждали: %s\n  было:  %s\n' "$1" "$2" "$3"; fi; }
has() { case "$3" in *"$2"*) pass=$((pass + 1)); printf 'ok   %s\n' "$1" ;; *) fail=$((fail + 1)); printf 'FAIL %s\n  нет %s в: %s\n' "$1" "$2" "$3" ;; esac; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/conf" "$W/state"
cp "$STUB/fixtures/spec.json" "$W/spec.json"
# схема настроек плагина — по ней служба settings проверяет и отдаёт умолчания
cp "$HERE/settings.schema.json" "$W/settings.schema.json"
printf '{"version":2,"outputs":{"direct":{"kind":"direct"},"cf":{"kind":"warp","count":2}}}\n' > "$W/spec.json"
cat > "$W/steer" <<'S'
#!/bin/sh
# ядро-заглушка: warp-scan печатает точки; группа "bad" — не отвечает
[ "$1" = warp-scan ] || exit 2
[ "$2" = bad ] && { echo "ядро не ответило" >&2; exit 1; }
# Подбор идёт, пока стенд не откроет ворота (файл scan-go): «идёт» и «второй запуск не стартует» проверяются на идущем
# подборе при любой нагрузке, а не в окне одной секунды. Без ворот — не дольше 10 с.
i=0; while [ ! -e "$S2_SANDBOX/scan-go" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
printf '{"ok":true,"points":[{"ip":"162.159.192.1","port":2408,"class":0,"loss":0,"rtt":31,"colo":"AMS","cc":"NL"}],"filtered":2}\n'
S
chmod 755 "$W/steer"
export PATH="$STUB/tools:$PATH" S2_SANDBOX="$W" STEER_PLUGIN_ID=warpbox-ui STEER_PLUGIN_DIR="$HERE" \
    STEER_PLUGIN_CONF="$W/conf" STEER_PLUGIN_STATE="$W/state" SPLIFY2_API=1 SPLIFY2_LIB="$STUB/lib.sh" SPLIFY2_HOST="$STUB/host"
call() { printf '%s' "${2:-{\}}" | sh "$HERE/rpc/warpbox" "$1"; }
j() { printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$2"; }

o="$(call defaults_get)"
check "defaults_get: умолчания схемы" "awg 1 latency" "$(j "$o" 'd["transport"]+" "+str(d["count"])+" "+d["pick"]')"
o="$(call defaults_set '{"transport":"masque","count":"3","pick":"order","exclude_countries":"RU,BY"}')"
check "defaults_set: записано" "True" "$(j "$o" 'd["ok"]')"
o="$(call defaults_get)"
check "  и прочитано" "masque 3 order RU,BY" "$(j "$o" 'd["transport"]+" "+str(d["count"])+" "+d["pick"]+" "+d["exclude_countries"]')"
o="$(call defaults_set '{"transport":"quic","count":"3","pick":"order","exclude_countries":""}')"
check "defaults_set: чужое значение — отказ" "False" "$(j "$o" 'd["ok"]')"
o="$(call defaults_set '{"transport":"awg","count":"300","pick":"latency","exclude_countries":""}')"
check "  число вне пределов — отказ" "False" "$(j "$o" 'd["ok"]')"

o="$(call scan '{"group":"../x"}')"
check "scan: небезопасное имя — отказ" "warp.bad_group" "$(j "$o" 'd["code"]')"
o="$(call scan '{"group":"direct"}')"
check "scan: выход не WARP — отказ" "warp.no_group" "$(j "$o" 'd["code"]')"
o="$(call scan_state '{"group":"cf"}')"
check "scan_state до подбора: не идёт, итога нет" "False None" "$(j "$o" 'str(d["running"])+" "+str(d["result"])')"
o="$(call scan '{"group":"cf"}')"
check "scan: запущен в фоне" "True" "$(j "$o" 'd["started"]')"
sleep 0.3
o="$(call scan_state '{"group":"cf"}')"
check "  идёт" "True" "$(j "$o" 'd["running"]')"
o="$(call scan '{"group":"cf"}')"
check "  второй запуск не стартует" "True" "$(j "$o" 'd["running"]')"
: > "$W/scan-go"
i=0; while [ $i -lt 30 ]; do
    [ "$(j "$(call scan_state '{"group":"cf"}')" 'd["running"]')" = False ] && break
    sleep 0.2; i=$((i + 1))
done
o="$(call scan_state '{"group":"cf"}')"
check "  закончился: точки и число отсеянных" "1 2" "$(j "$o" 'str(len(d["result"]["points"]))+" "+str(d["result"]["filtered"])')"
check "  время итога записано" "True" "$(j "$o" 'd["at"] > 0')"

# Подбор, закончившийся ничем, отдаёт причину, а не молчит.
printf '{"version":2,"outputs":{"direct":{"kind":"direct"},"bad":{"kind":"warp"}}}\n' > "$W/spec.json"
call scan '{"group":"bad"}' >/dev/null
i=0; while [ $i -lt 30 ]; do
    [ "$(j "$(call scan_state '{"group":"bad"}')" 'd["running"]')" = False ] && break
    sleep 0.2; i=$((i + 1))
done
o="$(call scan_state '{"group":"bad"}')"
check "подбор без ответа: причина из журнала" "False ядро не ответило" "$(j "$o" 'str(d["result"]["ok"])+" "+d["result"]["error"]')"
o="$(call нет_такого)"
has "неизвестный метод — отказ" "unknown_method" "$o"

printf '\nwarpbox-ui rpc: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
