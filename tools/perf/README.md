# Perf Tools

Минимальный набор скриптов для воспроизводимых замеров CPU/RAM/latency.

## 1) Снимок процесса

```bash
tools/perf/process_snapshot.sh <pid>
```

Вывод: `cpu_pct`, `rss_kb`, `threads`, `fds`.

## 2) Нагрузка на status endpoint (UI polling)

```bash
tools/perf/poll_status.py --url http://127.0.0.1:8000/api/v1/stream-status --requests 500 --concurrency 10
tools/perf/poll_status.py --url http://127.0.0.1:8000/api/v1/stream-status?lite=1 --requests 500 --concurrency 10
# если API закрыт auth:
tools/perf/poll_status.py --url http://127.0.0.1:8000/api/v1/stream-status --bearer <token>
```

Вывод: avg/p50/p95/p99 latency и RPS.
Дополнительно: `http_status`, `error_types`, `first_error` для быстрой диагностики 401/404/timeout.

## 3) Полный suite для before/after (polling + CPU/RSS samples)

```bash
PID=<astra_pid>
tools/perf/run_polling_suite.sh --pid "$PID" --base-url http://127.0.0.1:8000 --requests 1000 --concurrency 20
# если включена авторизация API:
tools/perf/run_polling_suite.sh --pid "$PID" --base-url http://127.0.0.1:8000 --bearer <token>
# или авто-логин перед запуском suite:
tools/perf/run_polling_suite.sh --pid "$PID" --base-url http://127.0.0.1:8000 --auth-user admin --auth-pass admin

# Сводная таблица по результатам
tools/perf/summarize_polling_suite.py --dir tools/perf/results/<timestamp>
```

Suite сохраняет:
- snapshot_before / snapshot_after
- latency JSON для full/lite endpoint
- секундные samples процесса во время нагрузки (`cpu_pct`, `rss_kb`, `threads`, `fds`)

## 3.1) Снятие инцидента (per-core/per-thread + softnet + perf)

Полезно, когда “одно ядро 100%” и стримы дёргаются.

```bash
PID=<astra_pid>
OUT=tools/perf/results/incident_$(date +%Y%m%d_%H%M%S)
tools/perf/capture_incident.sh "$PID" 15 "$OUT"
```

Сохраняет:
- top threads (PSR/%CPU)
- per-core load (mpstat), если доступно
- per-thread (pidstat), если доступно
- softnet drops (before/after)
- perf record/report (best-effort), если доступно

## 3.2) Smoke: Settings → General без перезапуска стримов

Проверяет, что безопасное изменение настроек (например `ui_status_polling_interval_sec`)
не роняет uptime выбранного стрима.

```bash
tools/perf/settings_no_restart_smoke.sh --base http://127.0.0.1:9060 --stream a014
```

Опции:
- `--user` / `--pass` — если не admin/admin
- `--token` — использовать готовый bearer token
- `--check-local-pid` — дополнительно сверять локальный PID ffmpeg
  (используйте только когда скрипт запускается на той же машине, где работает Astral)

## 3.3) Smoke: stream update scope (target-only reload)

Проверяет, что изменение одного stream через `PUT /api/v1/streams/<id>`
не роняет uptime контрольного stream.

```bash
tools/perf/stream_update_scope_smoke.sh \
  --base http://127.0.0.1:9060 \
  --target a014 \
  --control a019
```

## 3.4) Matrix smoke: безопасные Settings → General

Запускает набор ключей из General и проверяет, что uptime выбранного стрима не падает.
Опционально проверяет, что PID ffmpeg не меняется.

```bash
tools/perf/settings_general_matrix_smoke.py \
  --base http://127.0.0.1:9060 \
  --stream a014 \
  --check-local-pid \
  --out tools/perf/results/settings_matrix.md
```

## 4) Hotspot-проверка таймеров (P1.2)

```bash
PID=<astra_pid>
tools/perf/timer_hotspots.sh "$PID" 20 tools/perf/timer_hotspots_before.txt
# после изменений
tools/perf/timer_hotspots.sh "$PID" 20 tools/perf/timer_hotspots_after.txt
```

Linux: использует `perf`.  
macOS: использует встроенный `sample` (фолбэк).

Сравнивайте долю/наличие `asc_timer_*` и соседних call stack в отчётах до/после.
Если бинарник собран со `strip`, в отчёте будет предупреждение про отсутствие пользовательских символов.

## 5) Нагрузка на /play клиентами

```bash
tools/perf/play_clients.sh "http://127.0.0.1:8000/play/<stream_id>" 200 30
```

Где:
- `200` — число параллельных клиентов
- `30` — длительность клиента (сек)

## 6) Генерация мок‑стримов (без DVB)

```bash
tools/perf/generate_mock_streams.py --count 200 --out tools/perf/mock_streams.json
```

Создаёт JSON с N потоками для тестового импорта/нагрузки.

## 7) Mass UDP passthrough (legacy vs mmsg vs dataplane)

Сценарий: много “обычных” UDP passthrough стримов в одном процессе, без шардирования.

Подготовка:
- Linux host
- Собранный бинарник (`./stream` или `./astra`)
- `curl`, `python3`, опционально: `sysstat` (mpstat/pidstat), `perf`

Команда:

```bash
# legacy pipeline (без batching)
MODE=legacy COUNT=200 PPS=50 DURATION=30 tools/perf/passthrough_benchmark.sh

# legacy pipeline + recvmmsg/sendmmsg (opt-in)
MODE=mmsg COUNT=200 PPS=50 DURATION=30 tools/perf/passthrough_benchmark.sh

# dataplane (opt-in, Linux-only, eligible UDP->UDP streams)
MODE=dp COUNT=200 PPS=50 DURATION=30 tools/perf/passthrough_benchmark.sh
```

Результаты сохраняются в `tools/perf/results/passthrough_<ts>_<mode>/`:
- `snapshot_before.txt` / `snapshot_after.txt` (CPU/RSS/threads/fds)
- `capture_incident.sh` артефакты (per-core/per-thread/perf), если утилиты доступны

Замер “равномерно по ядрам”:
- `mpstat -P ALL 1` во время теста
- `pidstat -t -p <PID> 1` чтобы увидеть worker threads (dataplane)
