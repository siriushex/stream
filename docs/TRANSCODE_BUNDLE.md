# ASTRAL Transcode Bundle

Коротко: это self-contained пакет, в котором `astral` поставляется вместе с `ffmpeg`/`ffprobe`.
Пользователь распаковывает архив и запускает без установки системного ffmpeg.

## Что внутри
- `bin/astra` — основной бинарь.
- `bin/astral` — удобный wrapper, выставляет `ASTRA_BASE_DIR` и `ASTRA_EDITION=ASTRAL`.
- `bin/ffmpeg`, `bin/ffprobe` — bundled инструменты.
- `web/`, `scripts/` — UI и runtime.
- `LICENSES/` — лицензии и build-info.
- `run.sh` — быстрый запуск.

## Как собрать bundle

По умолчанию используется LGPL-профиль ffmpeg.

```bash
scripts/release/build_astral_bundle.sh --arch linux-x86_64 --profile lgpl
```

Для GPL-профиля (явно помечается в имени архива):

```bash
scripts/release/build_astral_bundle.sh --arch linux-x86_64 --profile gpl
```

Если нужно использовать локальные бинарники ffmpeg/ffprobe (без интернета):

```bash
scripts/release/build_astral_bundle.sh --ffmpeg-local /path/to/ffmpeg --ffprobe-local /path/to/ffprobe
```

Или скачать из своего источника (обязательно SHA256):

```bash
FFMPEG_URL=... \
FFMPEG_SHA256=... \
scripts/release/build_astral_bundle.sh
```

Артефакт появится в `./dist/` и будет сопровождаться `SHA256SUMS`.

## Как запустить

```bash
tar -xzf astral-transcode-<version>-linux-<arch>-lgpl.tar.gz
cd astral-transcode-<version>-linux-<arch>-lgpl
./run.sh scripts/server.lua -p 8000 --data-dir ./data --web-dir ./web
```

## Как проверить, что используется bundled ffmpeg
1) В логах старта сервера:
   - `[edition] ASTRAL (bundled tools: yes)`
   - `[tools] ffmpeg=.../bin/ffmpeg (bundle)`
2) Через API:

```bash
curl http://127.0.0.1:8000/api/v1/tools
```

Ожидается `ffmpeg_path_resolved` с `.../bin/ffmpeg` и `ffmpeg_bundled: true`.

## Как переопределить ffmpeg/ffprobe
Порядок приоритета:
1) настройки `ffmpeg_path` / `ffprobe_path`
2) env `ASTRA_FFMPEG_PATH` / `ASTRA_FFPROBE_PATH`
3) bundled `./bin/ffmpeg` / `./bin/ffprobe`
4) PATH

## Обновление bundled ffmpeg
Повторно запусти `build_astral_bundle.sh` с новым URL+SHA256.
Информация о сборке ffmpeg сохраняется в `LICENSES/FFMPEG_BUILD_INFO.txt`.

## Примечания по лицензиям
- По умолчанию используется LGPL-сборка ffmpeg.
- GPL-профиль помечается в имени архива `-gpl` и требует соблюдения условий GPL.
- Лицензии и notices лежат в `LICENSES/`.
