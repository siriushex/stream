# SKILL — Astral (fork Astra)

## Scope
- Astral — форк Astra с целью паритета функционала и близкого UX, без регрессий.
- Ничего из уже работающего не ломаем. Все новые фичи — add‑only, с безопасными дефолтами.
- Брендинг: Astral. Astra упоминать только при ссылках на документацию.

## Что уже сделано (зафиксировано)
- Inline‑редактирование OUTPUT list (стримы), включая строковые URL‑outputs.
- Переименование ID потоков и адаптеров с сохранением ссылок `dvb://`.
- Возможность сохранять стримы без outputs.
- Default backup mode = passive; алиас `backup_type: "disable"` → `disabled`.
- Ошибка “Failed to fetch” заменена на читабельные сообщения.
- HLSSplitter и Buffer скрываются/включаются через Settings → General.
- Disabled streams отображаются серым (не красным).
- EPG UI + экспорт (channels‑only XMLTV/JSON) + интервал экспорта.
- MPTS tab (General/NIT/Advanced) с сохранением `mpts_config`.
- Stream‑level `filter~` и SDT/EIT/no_reload флаги в UI + runtime.
- Password policy UI (min length + required character classes).
- Output modal advanced fields (HLS naming/round/ts, SCTP toggles, SRT bridge advanced).
- Output modal BISS key (per-output encryption).
- Advanced input options parity (cam/biss/cc_limit/bitrate_limit/no_analyze).
- Auth session TTL + CSRF + login rate limit settings (General).
- Stream defaults in General (timeouts/backup/keep-active).
- InfluxDB export settings + runtime push.
- Telegram alerts (UI + notifier + test endpoint + masking).
- Groups settings + stream group field (playlist group-title).
- Servers settings + test endpoint.
- Softcam settings UI (list + modal) backed by settings.
- CAS settings wired; License view read-only via `/api/v1/license`.
- Dashboard stream tiles: compact/expanded modes with persisted state (localStorage).
- Apply UX: “Applying…” indicator + partial list refresh (no full re-render).
- Root UI path `/` (serves UI without `/index.html`).
- Reduced UI polling frequency + pause when tab hidden; 1s cache for `/api/v1/stream-status`.

## Invariants (не нарушать)
- API `/api/v1/*` не ломаем. Новые эндпоинты — только add‑only.
- Конфиги backward‑compatible: новые ключи опциональны, дефолты не меняют поведение.
- UI существующих фич не удаляем. Добавляем новые поля/вкладки.
- Никаких правок прямо на сервере: изменения только в репо, затем деплой.
- DEV/TEST только на `178.212.236.2` (ssh `-p 40242 -i ~/.ssh/root_blast`). `178.212.236.6` = PROD: не использовать для разработки/тестов/деплоя из Codex (только read-only диагностика).
- Список тестовых инстансов: только `178.212.236.2` (исключить `178.212.236.6`).
- Производительность в приоритете: минимальная нагрузка на CPU/RAM/IO. Фоновые таймеры и частый polling включать только при явной необходимости; по умолчанию использовать on‑demand и кэширование.

## Multi-agent coordination
- Следовать `docs/engineering/TEAM_WORKFLOW.md` и `.github/CODEOWNERS`.
- Ветки только `codex/<agent>/<topic>`, изменения — небольшими коммитами.
- Все изменения утверждает single owner: `@siriushex`.
- Всегда обновляй `CHANGELOG.md` и `docs/PARITY.md` (если меняется функционал).
- PR обязателен, прямые пуши в `main` запрещены.
- CI проверяет формат ветки и наличие записи в `CHANGELOG.md`.
- Перед началом работы всегда делай `git pull --rebase`, чтобы синхронизироваться с актуальной версией.
- После изменений обязательно делай commit и push.
- Если при pull возникают конфликты — решать их вручную.

## Репозиторий (ключевые точки входа)
- `main.c` — entrypoint бинарника.
- `scripts/server.lua` — HTTP сервер, UI, API, HLS/HTTP Play.
- `scripts/api.lua` — REST API.
- `scripts/stream.lua` — runtime стримов, inputs/outputs.
- `scripts/config.lua` — SQLite конфиг/миграции.
- `scripts/runtime.lua` — status/sessions/monitoring.
- `modules/mpegts/channel.c` — remap/service/cas/PID‑логика.
- `web/index.html`, `web/app.js`, `web/styles.css` — UI.

## Где смотреть полный реестр API/настроек
- Полный API и settings — в `README.md`.
- Полный workflow и smoke‑tests — в `AGENT.md`.

## План и паритет
- План разработки: `PLAN.md`
- Roadmap: `docs/ROADMAP.md`
- Матрица паритета: `docs/PARITY.md`

## Правила доработок (чтобы не терялись обновления)
- Всегда обновлять `CHANGELOG.md` на каждое изменение.
- Обновлять `docs/PARITY.md` (матрица “Docs → Astral”) при каждой фиче.
- Новые таблицы/поля → миграции в `scripts/config.lua`.
- Ошибки сети/валидации должны быть читабельны в UI.

## Деплой и проверка
- Следовать workflow из `AGENT.md` (rsync → configure → make → smoke tests).
