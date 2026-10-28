#!/bin/sh
# Сборка плагина recheck в .s2p по архитектурам. Движок steer-dpi-live — закрытая программа из репозитория recheck:
# его собирает `sh build.sh` там (статически, musl и OpenSSL), сюда он приезжает готовым файлом.
#
#   RECHECK_ENGINE_DIR=<recheck>/build sh tools/build-recheck.sh              без подписи, в plugins/dist
#   S2P_KEY=ключ.sec RECHECK_ENGINE_DIR=… sh tools/build-recheck.sh           с подписью
#   RECHECK_ARCH=x86_64 …                                                     одна архитектура
#
# Каталог движков — <каталог>/<архитектура>/steer-dpi-live. В архиве ничего лишнего: манифест, скрипты, правила nft,
# словари, лицензии и движок нужной архитектуры. Исходник плагина остаётся без движка: `s2p lint --official plugins/recheck`
# и стенды (tests/recheckmatch.sh) его не требуют.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SDK="${PLUGIN_SDK:-$REPO/../../splicicd/plugin-sdk}"
if command -v s2p >/dev/null 2>&1; then S2P="$(command -v s2p)"
elif [ -x "$SDK/bin/s2p" ]; then S2P="$SDK/bin/s2p"
else echo "нет инструмента s2p: положите его в PATH или задайте PLUGIN_SDK (каталог plugin-sdk)" >&2; exit 1; fi
ENGINES="${RECHECK_ENGINE_DIR:?нужен RECHECK_ENGINE_DIR — каталог с <архитектура>/steer-dpi-live из репозитория recheck}"
OUT="${S2P_OUT_DIR:-$REPO/plugins/dist}"
mkdir -p "$OUT"
ARCHES="${RECHECK_ARCH:-$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["arch"]))' "$REPO/plugins/recheck/plugin.json")}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
for arch in $ARCHES; do
    eng="$ENGINES/$arch/steer-dpi-live"
    [ -x "$eng" ] || { echo "нет движка для $arch: $eng (в репозитории recheck: RECHECK_ARCH=$arch sh build.sh)" >&2; exit 1; }
    rm -rf "$stage/recheck"
    cp -r "$REPO/plugins/recheck" "$stage/recheck"
    # Интерфейс панели (ui-src) собирает `s2p build` командой из s2p.json: зависимости npm — из каталога плагина.
    rm -rf "$stage/recheck/node_modules" "$stage/recheck/ui"
    [ -d "$REPO/plugins/recheck/node_modules" ] && ln -s "$(readlink -f "$REPO/plugins/recheck/node_modules")" "$stage/recheck/node_modules"
    cp "$eng" "$stage/recheck/bin/steer-dpi-live"
    chmod 0755 "$stage/recheck/bin/steer-dpi-live"
    "$S2P" lint --official "$stage/recheck"
    if [ -n "${S2P_KEY:-}" ]; then "$S2P" build "$stage/recheck" --arch "$arch" --key "$S2P_KEY" -o "$OUT"
    else "$S2P" build "$stage/recheck" --arch "$arch" --unsigned -o "$OUT"; fi
done
