# PERF AFTER (после оптимизаций)

Дата: 2026-02-11  
Инстанс: stage `178.212.236.2:9060` (`astral@prod.service`)  
Коммит: локальная рабочая ветка (после P1.2 heap timer)

## Команды

```bash
PID=<astra_pid>
tools/perf/process_snapshot.sh "$PID"

tools/perf/run_polling_suite.sh --pid "$PID" --base-url http://127.0.0.1:8000 --requests 1000 --concurrency 20 [--bearer <token>]
tools/perf/summarize_polling_suite.py --dir tools/perf/results/<timestamp>

tools/perf/timer_hotspots.sh "$PID" 20 tools/perf/timer_hotspots_after.txt

tools/perf/play_clients.sh "http://127.0.0.1:8000/play/<stream_id>" 200 30

# Mass UDP passthrough (legacy/mmsg/dataplane)
MODE=legacy COUNT=200 PPS=50 DURATION=30 tools/perf/passthrough_benchmark.sh
MODE=mmsg   COUNT=200 PPS=50 DURATION=30 tools/perf/passthrough_benchmark.sh
MODE=dp     COUNT=200 PPS=50 DURATION=30 tools/perf/passthrough_benchmark.sh
```

## Результаты (после)

| Сценарий | CPU % | RSS MB | p95 API ms | Threads | FDs | Δ к baseline |
|---|---:|---:|---:|---:|---:|---|
| Idle | TBD | TBD | TBD | TBD | TBD | TBD |
| 200 streams, no transcode | TBD | TBD | TBD | TBD | TBD | TBD |
| + transcode (часть потоков) | TBD | TBD | TBD | TBD | TBD | TBD |
| /play 200 clients | TBD | TBD | TBD | TBD | TBD | TBD |
| 200 UDP passthrough (legacy) | TBD | TBD | TBD | TBD | TBD | TBD |
| 200 UDP passthrough (mmsg) | TBD | TBD | TBD | TBD | TBD | TBD |
| 200 UDP passthrough (dataplane) | TBD | TBD | TBD | TBD | TBD | TBD |

## Timer hotspots (P1.2)

- Файл: `tools/perf/timer_hotspots_after.txt`
- Доля `asc_timer_*`: TBD
- Δ к baseline: TBD

## Вывод

- TBD

## Локальный короткий чек (macOS, 2026-02-11)

- Сервер: `./stream scripts/server.lua -a 127.0.0.1 -p 18080 --data-dir ./data`
- Результаты: `tools/perf/results/20260211_183927`

| case | ok | errors | rps | p95 ms | p99 ms | avg cpu % | avg rss MB | avg threads | avg fds |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| status_full | 400 | 0 | 2633.76 | 8.43 | 22.78 | 0.7 | 13.34 | 2.0 | 21.0 |
| status_lite | 400 | 0 | 2559.02 | 8.81 | 15.99 | 1.8 | 17.77 | 2.0 | 22.0 |

Примечание: это быстрый smoke на macOS с малым числом потоков. Для корректного before/after по P1.2 нужен повтор на Linux стенде с `perf` и целевой нагрузкой (200+ streams).

## Короткий чек на `.2` (Linux, 2026-02-11)

- Сервер: `178.212.236.2:9060`, процесс `astral@prod.service`
- Результаты: `/home/hex/stream/tools/perf/results/prod_p12_20260211_184836`

| case | ok | errors | rps | p95 ms | p99 ms | avg cpu % | avg rss MB | avg threads | avg fds |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| status_full | 300 | 0 | 1413.69 | 11.15 | 17.09 | 7.9 | 35.22 | 4.0 | 17.0 |
| status_lite | 300 | 0 | 1380.31 | 12.41 | 14.74 | 8.0 | 39.87 | 4.0 | 16.0 |

Дополнительно:
- process snapshot: `cpu_pct=8.3 rss_kb=36288 threads=4 fds=17`
- timer hotspots: `/home/hex/stream/tools/perf/results/prod_p12_20260211_185523_timer_hotspots.txt`
- вывод perf показал в основном kernel `hrtimer_*`; пользовательские timer symbols скрыты из-за strip бинарника.

## Smoke: Settings без forced restart (Linux `.2`, 2026-02-12)

Проверка выполнена после фикса `PUT /api/v1/settings -> reload_runtime(false)`.

Команды:

```bash
/home/hex/stream/tools/perf/settings_no_restart_smoke.sh \
  --base http://127.0.0.1:9060 \
  --stream a014 \
  --check-local-pid

/home/hex/stream/tools/perf/settings_no_restart_all_streams.sh \
  --base http://127.0.0.1:9060 \
  --setting-key ui_status_polling_interval_sec \
  --setting-value 0.5

/home/hex/stream/tools/perf/settings_general_matrix_smoke.py \
  --base http://127.0.0.1:9060 \
  --stream a014 \
  --check-local-pid
```

Результаты:
- single smoke: `uptime 384 -> 386`, `ffmpeg pid 1890080 -> 1890080` (PASS)
- all-streams smoke: `checked_active_streams=11`, uptime drop не обнаружен (PASS)
- matrix smoke (safe keys):

| key | uptime (a014) | ffmpeg pid | status |
|---|---:|---|---|
| log_level | 213→215 | 1891748→1891748 | PASS |
| ui_status_polling_interval_sec | 215→217 | 1891748→1891748 | PASS |
| ui_status_lite_enabled | 217→219 | 1891748→1891748 | PASS |
| performance_aggregate_stream_timers | 219→222 | 1891748→1891748 | PASS |
| performance_aggregate_transcode_timers | 222→224 | 1891748→1891748 | PASS |
| observability_system_rollup_enabled | 224→226 | 1891748→1891748 | PASS |
| lua_gc_step_units | 226→228 | 1891748→1891748 | PASS |

Вывод:
- безопасные изменения в `Settings -> General` больше не вызывают forced restart stream/transcode.
- контрольный forced reload (`/api/v1/reload-internal` без `force=0`) по-прежнему рестартит пайплайн, как и ожидается.
