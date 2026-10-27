#!/bin/sh
# Сборка плагинов (plugins/<id>) в .s2p инструментом SDK: `s2p lint --official`, затем `s2p build`.
#
#   sh plugins/build.sh                       lint и сборка всех плагинов в plugins/dist, без подписи
#   S2P_KEY=ключ.sec sh plugins/build.sh      с подписью (так собирает выпуск)
#   sh plugins/build.sh recheck               один плагин
#
# s2p ищется в PATH, затем в $PLUGIN_SDK/bin; если его нет, собирается из исходников SDK (`sh build.sh`, Go 1.21+).
# recheck несёт закрытый движок по архитектурам: его .s2p собирает tools/build-recheck.sh (RECHECK_ENGINE_DIR — каталог
# build репозитория recheck); без RECHECK_ENGINE_DIR здесь для него только lint.
#
# Плагин с файлом steer.src вместо plugin.json (tgws — мост Telegram) держит исходник в дереве ядра steer
# (STEER_PATH в steer.src): программа на C стоит на TLS и стороне плагина в API ядра (src/plugkit), и собирает
# её дерево steer — `STEER_ARCH=<арх> ./build.sh` кладёт её в build/libs/<арх>/plugins/<id>/bin/<id>
# (build/build-libs.sh, PLUGINS_EXTENDED в build/sources.mk). Здесь каталог плагина берётся из дерева steer,
# `@VERSION@` манифеста — версия дерева (VERSION), программа — из его сборки; архив — на каждую архитектуру,
# под которую она собрана. STEER_DIR — дерево steer (по умолчанию ../../splicicd/steer), STEER_LIBS — раскладки
# по архитектурам (по умолчанию $STEER_DIR/build/libs).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
SDK="${PLUGIN_SDK:-$HERE/../../splicicd/plugin-sdk}"
if command -v s2p >/dev/null 2>&1; then S2P="$(command -v s2p)"
elif [ -x "$SDK/bin/s2p" ]; then S2P="$SDK/bin/s2p"
elif [ -f "$SDK/build.sh" ]; then
    (cd "$SDK" && S2P_OUT="${TMPDIR:-/tmp}/s2p-bin.$$" sh build.sh >/dev/null) || exit 1
    S2P="${TMPDIR:-/tmp}/s2p-bin.$$/s2p"
else
    echo "нет инструмента s2p: положите его в PATH или задайте PLUGIN_SDK (каталог plugin-sdk)" >&2; exit 1
fi
OUT="${S2P_OUT_DIR:-$HERE/dist}"
mkdir -p "$OUT"
STEER_DIR="${STEER_DIR:-$HERE/../../splicicd/steer}"
STEER_LIBS="${STEER_LIBS:-$STEER_DIR/build/libs}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/s2p-ext.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
# Плагин с исходником в дереве steer: архив на каждую архитектуру, под которую собрана программа.
from_steer() {  # ID
    _sp="$(sed -n 's/^STEER_PATH=//p' "$HERE/$1/steer.src")"
    _src="$STEER_DIR/$_sp"
    [ -f "$_src/plugin.json" ] || { echo "$1: в дереве steer нет $_sp/plugin.json (STEER_DIR=$STEER_DIR)" >&2; exit 1; }
    _ver="$(cat "$STEER_DIR/VERSION")"
    _n=0
    for _lib in "$STEER_LIBS"/*/; do
        _prog="$_lib/plugins/$1/bin/$1"
        [ -x "$_prog" ] || continue
        _arch="$(basename "$_lib")"
        _d="$STAGE/$_arch/$1"
        rm -rf "$_d"; mkdir -p "$_d/bin"
        cp -R "$_src/." "$_d/"
        sed -i "s/\"@VERSION@\"/\"$_ver\"/" "$_d/plugin.json"
        cp "$_prog" "$_d/bin/$1"
        chmod 0755 "$_d/bin/$1"
        "$S2P" lint --official "$_d"
        if [ -n "${S2P_KEY:-}" ]; then "$S2P" build "$_d" --arch "$_arch" --key "$S2P_KEY" -o "$OUT"
        else "$S2P" build "$_d" --arch "$_arch" --unsigned -o "$OUT"; fi
        _n=$((_n + 1))
    done
    [ "$_n" -gt 0 ] || { echo "$1: программа не собрана ни под одну архитектуру — в steer: STEER_ARCH=<арх> ./build.sh" \
        "($STEER_LIBS/<арх>/plugins/$1/bin/$1)" >&2; exit 1; }
}
[ $# -gt 0 ] || set -- $(cd "$HERE" && for d in */; do { [ -f "$d/plugin.json" ] || [ -f "$d/steer.src" ]; } && echo "${d%/}"; done)
for id in "$@"; do
    if [ -f "$HERE/$id/steer.src" ]; then from_steer "$id"; continue; fi
    # --official: плагины репозитория пользуются платформой только через её API (splify2-api, раздел 9).
    "$S2P" lint --official "$HERE/$id"
    if [ "$id" = recheck ]; then
        [ -n "${RECHECK_ENGINE_DIR:-}" ] || { echo "recheck: нет RECHECK_ENGINE_DIR — собрана только проверка"; continue; }
        PLUGIN_SDK="$SDK" S2P_OUT_DIR="$OUT" sh "$HERE/../tools/build-recheck.sh"
        continue
    fi
    if [ -n "${S2P_KEY:-}" ]; then "$S2P" build "$HERE/$id" --key "$S2P_KEY" -o "$OUT"
    else "$S2P" build "$HERE/$id" --unsigned -o "$OUT"; fi
done
