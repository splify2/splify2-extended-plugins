#!/bin/sh
# Стенд плагина desktop-api: шлюз /v1/... (ucode) выставляется плагином, а не пакетом splify2.
#
#   PLUGIN_SDK=<plugin-sdk>  sh tests/desktopapimatch.sh
#
#   1  s2p lint --official и compat с splify2-api 1.2 (splify2.cgi, право splify2.cgi);
#   2  словари i18n/backend: те же ключи, что у английских текстов шлюза, подстановки на месте, русский — по-русски;
#   3  шлюз настоящим ucode (образ openwrt/rootfs в docker; нет docker — раздел пропущен): синтаксис, версия из
#      манифеста плагина через ссылку из каталога CGI, отказы кодом (error, code, args), перевод по словарю ВКЛЮЧЁННОГО
#      плагина, английский при выключенном словаре и в языке без словаря.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PLUGIN="$REPO/plugins/desktop-api"
SDK="${PLUGIN_SDK:-$REPO/../../splicicd/plugin-sdk}"
SDK="$(cd "$SDK" && pwd)"
S2P="$SDK/bin/s2p"
[ -x "$S2P" ] || { echo "desktopapimatch: нет $S2P"; exit 2; }
pass=0 fail=0
check() {
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
        fail=$((fail + 1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
    fi
}
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# ---- 1. lint, compat -----------------------------------------------------------------------------------------------------
"$S2P" lint --official "$PLUGIN" >"$tmp/lint" 2>&1; check "lint --official чист" "0" "$?"
sh "$SDK/tests/compat/run.sh" "$PLUGIN" 1.2 >"$tmp/compat" 2>&1; check "compat со splify2-api 1.2" "0" "$?"
check "шлюз исполняемый, в нём нет русских текстов вне комментариев" "yes;0" \
    "$([ -x "$PLUGIN/cgi/splify2-api" ] && echo yes || echo no);$(python3 -c 'import re,sys; print(sum(1 for l in open(sys.argv[1], encoding="utf-8") if not l.lstrip().startswith("//") and re.search("[А-Яа-яЁё]", l)))' "$PLUGIN/cgi/splify2-api")"

# ---- 2. словари ----------------------------------------------------------------------------------------------------------
python3 - "$PLUGIN" >"$tmp/dict" <<'PY'
import json, re, sys
p = sys.argv[1]
src = open(p + "/cgi/splify2-api", encoding="utf-8").read()
body = src[src.index("const TEXTS = {"):]; body = body[:body.index("};")]
texts = {"gateway." + k: v for k, v in re.findall(r"^\t(\w+): '(.*)',$", body, re.M)}
en = json.load(open(p + "/i18n/backend/en.json", encoding="utf-8"))
ru = json.load(open(p + "/i18n/backend/ru.json", encoding="utf-8"))
used = set(re.findall(r"fail\(\d+, '\w+', '(\w+)'", src)) | set(re.findall(r"refusal\('(\w+)'", src)) | \
       set(re.findall(r"return \[\d+, '\w+', '(\w+)'", src))
ph = lambda t: sorted(re.findall(r"\{(\w+)\}", t))
print("en-ключи", sorted(en) == sorted(texts))
print("ru-ключи", sorted(ru) == sorted(texts))
print("en-тексты", en == texts)
print("подстановки", all(ph(ru[k]) == ph(texts[k]) for k in texts))
print("ru-кириллица", all(re.search("[А-Яа-я]", v) or ph(v) for v in ru.values()))
print("все-тексты-используются", used == {k.split(".", 1)[1] for k in texts})
PY
for k in en-ключи ru-ключи en-тексты подстановки ru-кириллица все-тексты-используются; do
    check "словари: $k" "True" "$(sed -n "s/^$k //p" "$tmp/dict")"
done

# ---- 3. шлюз настоящим ucode ---------------------------------------------------------------------------------------------
IMG="${UCODE_IMAGE:-openwrt/rootfs:x86-64-24.10.2}"
if ! docker image inspect "$IMG" >/dev/null 2>&1; then echo "desktopapimatch: нет docker-образа $IMG - раздел 3 пропущен"
else
    R="$tmp/root"; mkdir -p "$R/plugins" "$R/www/cgi-bin"
    cp -r "$PLUGIN" "$R/plugins/desktop-api"
    printf '{"schema":1,"plugins":{"desktop-api":{"state":"enabled"}}}\n' > "$R/state.json"
    printf '{"schema":1,"plugins":{"desktop-api":{"state":"disabled"}}}\n' > "$R/state-off.json"
    ln -s /plugins/desktop-api/cgi/splify2-api "$R/www/cgi-bin/splify2-api"
    gw() {  # ПЕРЕМЕННЫЕ... — запрос к шлюзу по ссылке из каталога CGI; последняя строка ответа
        docker run --rm --entrypoint sh -v "$R:/r:ro" openwrt/rootfs:x86-64-24.10.2 -c \
            'mkdir -p /plugins /www; cp -a /r/plugins/. /plugins/; cp -a /r/www/. /www/; cp /r/state*.json /; env "$@" ucode /www/cgi-bin/splify2-api | tail -1' sh \
            REQUEST_METHOD=GET PLUGIN_ROOT=/plugins "$@" 2>&1
    }
    pj() { python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(eval(sys.argv[1]))' "$1"; }
    docker run --rm --entrypoint sh -v "$PLUGIN:/p:ro" "$IMG" -c 'ucode -c /p/cgi/splify2-api' >/dev/null 2>&1
    check "шлюз: синтаксис ucode" "0" "$?"
    out="$(gw PATH_INFO=/v1/info PLUGIN_STATE=/state.json)"
    check "/v1/info: версия — из манифеста плагина (через ссылку CGI)" "1.0.0" "$(printf '%s' "$out" | pj 'd["version"]')"
    out="$(gw PATH_INFO=/v1/nowhere PLUGIN_STATE=/state.json S2_LANG=en)"
    check "отказ: слово error, code gateway.<ключ>, пустой args, английский текст" "no_route;gateway.no_route;{};No such address" \
        "$(printf '%s' "$out" | pj 'd["error"]');$(printf '%s' "$out" | pj 'd["code"]');$(printf '%s' "$out" | pj 'd["args"]');$(printf '%s' "$out" | pj 'd["message"]')"
    out="$(gw PATH_INFO=/v1/nowhere PLUGIN_STATE=/state.json S2_LANG=ru)"
    check "русский — по словарю включённого плагина" "Нет такого адреса;no_route" "$(printf '%s' "$out" | pj 'd["message"]');$(printf '%s' "$out" | pj 'd["error"]')"
    out="$(gw PATH_INFO=/v1/nowhere PLUGIN_STATE=/state.json S2_LANG=ru-RU)"
    check "ru-RU падает на ru" "Нет такого адреса" "$(printf '%s' "$out" | pj 'd["message"]')"
    out="$(gw PATH_INFO=/v1/nowhere PLUGIN_STATE=/state-off.json S2_LANG=ru)"
    check "плагин выключен — словаря нет, английский" "No such address" "$(printf '%s' "$out" | pj 'd["message"]')"
    out="$(gw PATH_INFO=/v1/nowhere PLUGIN_STATE=/state.json S2_LANG=de)"
    check "язык без словаря — английский" "No such address" "$(printf '%s' "$out" | pj 'd["message"]')"
    out="$(gw PATH_INFO=/v1/call/x PLUGIN_STATE=/state.json S2_LANG=ru)"
    check "подстановка {verb}: значение в args и в тексте" "POST;Нужен POST;gateway.bad_verb" \
        "$(printf '%s' "$out" | pj 'd["args"]["verb"]');$(printf '%s' "$out" | pj 'd["message"]');$(printf '%s' "$out" | pj 'd["code"]')"
    out="$(gw PATH_INFO=/v1/devices PLUGIN_STATE=/state.json S2_LANG=en)"
    check "без токена: 401 no_token" "no_token;An access token is required" "$(printf '%s' "$out" | pj 'd["error"]');$(printf '%s' "$out" | pj 'd["message"]')"
fi
echo "desktopapimatch: $pass прошло, $fail упало"
[ "$fail" = 0 ]
