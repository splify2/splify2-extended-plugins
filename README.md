# splify2-extended-plugins

Расширенные плагины платформы splify2/steer: то, что не входит в основную поставку, но делается тем же API и ставится
из вкладки «Плагины» splify2. Пользуются платформой только через её API
([plugin-sdk](https://github.com/splify2/plugin-sdk)): `s2p lint --official` чистый, тест совместимости SDK проходит.

| Плагин | Что делает |
|---|---|
| [`recheck`](plugins/recheck) | обход блокировок по содержимому трафика: служба под надзором steer, правила nft в слотах ядра, настройки и состояние во вкладке «Плагины». Движок `steer-dpi-live` — закрытый (репозиторий recheck), в архив ложится готовым файлом |
| [`desktop-api`](plugins/desktop-api) | шлюз `/v1/...` для приложений вне LuCI (Desktop): вход устройств по токенам, вызовы, задания, события ядра. Файл `cgi/splify2-api` (ucode) хост splify2 выставляет в `/www/cgi-bin`, пока плагин включён (`splify2.cgi`, splify2-api 1.2, право `splify2.cgi`); устройства — в `/etc/steer/plugins/conf/desktop-api`. Тексты отказов — кодами `gateway.*`, словари `i18n/backend` |
| [`tgws`](plugins/tgws) | мост Telegram: соединения клиентов сети с дата-центрами Telegram уходят веб-сокетом через Cloudflare, в приложении ничего не настраивается; пул доменов, пути дата-центров и туннели WARP — в настройках во вкладке «Плагины». Исходник — в дереве ядра steer (`plugins/tgws`, программа на C), отсюда собирается архив |

## Сборка и проверка

```sh
sh plugins/build.sh                      # lint и сборка плагинов в plugins/dist (без подписи)
S2P_KEY=ключ.sec sh plugins/build.sh     # с подписью
RECHECK_ENGINE_DIR=<recheck>/build sh plugins/build.sh recheck   # recheck: .s2p по архитектурам с движком
STEER_DIR=<steer> sh plugins/build.sh tgws   # tgws: .s2p по архитектурам, под которые steer собрал программу (./build.sh)

STEER=<steer>/build/steer PLUGIN_SDK=<plugin-sdk> sh tests/recheckmatch.sh   # стенд recheck
PLUGIN_SDK=<plugin-sdk> sh tests/desktopapimatch.sh   # стенд desktop-api (ucode из docker-образа openwrt/rootfs)
```

Стенд recheck запускает службу под настоящим демоном steer (ядро 2.1, steer-api 1.2) с движком-заглушкой и проверяет
правила nft настоящим `nft -c`, настройки, методы `status` и `forget`. Поведение самого движка проверяют стенды
репозитория recheck.
