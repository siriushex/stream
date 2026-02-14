# Build profiles (FULL / LITE)

Stream Hub можно собрать в двух вариантах.
Снаружи это один и тот же продукт, но набор функций отличается.

## Коротко

- **FULL**: есть транскод, ladder/publish, функции на базе `ffmpeg`.
- **LITE (no transcode)**: без транскода. Бинарник проще по зависимостям и легче поставить на "чистую" систему.

## Что доступно в каком профиле

| Функция | FULL | LITE |
|---|---:|---:|
| Relay (UDP/HTTP-TS и т.д.) | ✅ | ✅ |
| Backup / failover | ✅ | ✅ |
| SoftCAM | ✅ | ✅ |
| Remap / Service / MPTS | ✅ | ✅ |
| Web UI + API | ✅ | ✅ |
| Transcode | ✅ | ❌ |
| Ladder + publish (HLS/DASH/HTTP-TS publish) | ✅ | ❌ |
| Audio Fix | ✅ | ❌ |
| PNG to Stream | ✅ | ❌ |
| Create radio | ✅ | ❌ |

!!! note "Про конфиги"
    Если в конфиге есть блоки `transcode`, в LITE они не должны ломать запуск.
    Они просто игнорируются.

## Как понять, какая сборка установлена

Посмотрите строку версии в логах или в выводе `--help`:

```bash
/usr/local/bin/stream --help
```

Ищите:

- `Build: FULL`
- `Build: LITE (no transcode)`

## Готовые бинарники (скачать)

- **FULL**: `https://stream.centv.ru/stream` (то же самое: `https://stream.centv.ru/stream-linux-x86_64`)
- **LITE (no transcode)**: `https://stream.centv.ru/stream-linux-x86_64-lite`

!!! tip "Через installer"
    Можно поставить конкретный артефакт так:

    ```bash
    curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- \
      --mode binary --runtime-only --artifact stream-linux-x86_64-lite
    ```

## Как собрать FULL из исходников

```bash
git clone https://github.com/siriushex/stream.git
cd stream
./configure.sh
make -j
sudo make install
```

После установки проверьте:

```bash
/usr/local/bin/stream --help
```

## Как собрать LITE из исходников

```bash
git clone https://github.com/siriushex/stream.git
cd stream
./configure.sh --without-transcode
make -j
sudo make install
```

## Как переключиться FULL <-> LITE на сервере

1. Обновите бинарник `/usr/local/bin/stream` (через installer или сборку).
2. Перезапустите сервис/инстанс:

```bash
sudo systemctl restart stream@prod
```

## Когда выбирать LITE

- нужен стабильный relay без транскода;
- сервер "старый" и проще избежать сложных зависимостей;
- важнее простая установка и минимальные риски по библиотекам.

## Когда выбирать FULL

- нужен транскод;
- нужен ladder/publish;
- нужен PNG to Stream или Create radio.
