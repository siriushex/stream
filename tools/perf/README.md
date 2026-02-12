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
