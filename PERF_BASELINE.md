# PERF BASELINE (до оптимизаций)

Дата: __заполнить__  
Инстанс: __test/stage__  
Коммит: __заполнить__

## Команды

```bash
# 1) Снимок процесса
PID=<astra_pid>
tools/perf/process_snapshot.sh "$PID"

# 2) Suite polling (full/lite + samples CPU/RSS)
tools/perf/run_polling_suite.sh --pid "$PID" --base-url http://127.0.0.1:8000 --requests 1000 --concurrency 20 [--bearer <token>]
tools/perf/summarize_polling_suite.py --dir tools/perf/results/<timestamp>

# 3) Hotspots таймеров
tools/perf/timer_hotspots.sh "$PID" 20 tools/perf/timer_hotspots_before.txt

# 4) Нагрузка /play (пример)
tools/perf/play_clients.sh "http://127.0.0.1:8000/play/<stream_id>" 200 30

# 5) Mass UDP passthrough (legacy/mmsg/dataplane)
MODE=legacy COUNT=200 PPS=50 DURATION=30 tools/perf/passthrough_benchmark.sh
MODE=mmsg   COUNT=200 PPS=50 DURATION=30 tools/perf/passthrough_benchmark.sh
MODE=dp     COUNT=200 PPS=50 DURATION=30 tools/perf/passthrough_benchmark.sh
```

## Результаты (до)

| Сценарий | CPU % | RSS MB | p95 API ms | Threads | FDs | Примечание |
|---|---:|---:|---:|---:|---:|---|
| Idle | TBD | TBD | TBD | TBD | TBD | |
| 200 streams, no transcode | TBD | TBD | TBD | TBD | TBD | |
| + transcode (часть потоков) | TBD | TBD | TBD | TBD | TBD | |
| /play 200 clients | TBD | TBD | TBD | TBD | TBD | |
| 200 UDP passthrough (legacy) | TBD | TBD | TBD | TBD | TBD | |
| 200 UDP passthrough (mmsg) | TBD | TBD | TBD | TBD | TBD | |
| 200 UDP passthrough (dataplane) | TBD | TBD | TBD | TBD | TBD | |

## Hot functions (perf top/record)

- TBD

## Timer hotspots (P1.2)

- Файл: `tools/perf/timer_hotspots_before.txt`
- Доля `asc_timer_*`: TBD
