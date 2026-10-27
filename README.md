# splify2-extended-plugins

Расширенные плагины платформы splify2/steer: то, что не входит в основную поставку, но делается тем же API и ставится
из вкладки «Плагины» splify2. Пользуются платформой только через её API
([plugin-sdk](https://github.com/splify2/plugin-sdk)): `s2p lint --official` чистый, тест совместимости SDK проходит.

| Плагин | Что делает |
|---|---|
| [`recheck`](plugins/recheck) | обход блокировок по содержимому трафика: служба под надзором steer, правила nft в слотах ядра, настройки и состояние во вкладке «Плагины». Движок `steer-dpi-live` — закрытый (репозиторий recheck), в архив ложится готовым файлом |

## Сборка и проверка

```sh
sh plugins/build.sh                      # lint и сборка плагинов в plugins/dist (без подписи)
S2P_KEY=ключ.sec sh plugins/build.sh     # с подписью
RECHECK_ENGINE_DIR=<recheck>/build sh plugins/build.sh recheck   # recheck: .s2p по архитектурам с движком

STEER=<steer>/build/steer PLUGIN_SDK=<plugin-sdk> sh tests/recheckmatch.sh   # стенд recheck
```

Стенд recheck запускает службу под настоящим демоном steer (ядро 2.1, steer-api 1.2) с движком-заглушкой и проверяет
правила nft настоящим `nft -c`, настройки, методы `status` и `forget`. Поведение самого движка проверяют стенды
репозитория recheck.
