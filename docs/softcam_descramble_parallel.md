# SoftCAM: Parallel Descramble (Per-Stream Worker Thread)

Цель: снизить нагрузку на **одно ядро CPU** при включённом SoftCAM за счёт выноса DVB-CSA decrypt (descrambling)
в отдельный поток **на каждый decrypt-инстанс/стрим**.

Важно:
- Это **opt-in** (по умолчанию выключено).
- Смысл CA (ECM/CW) не меняется. Меняется только исполнение CPU-heavy decrypt.
- Порядок TS пакетов сохраняется.

## Как включить

### 1) Через Settings → General (recommended)

Параметры:
- `softcam_descramble_parallel` = `off` | `per_stream_thread`
- `softcam_descramble_batch_packets` (default: 64)
- `softcam_descramble_queue_depth_batches` (default: 16)
- `softcam_descramble_worker_stack_kb` (default: 256)
- `softcam_descramble_drop_policy` = `drop_oldest` | `drop_newest` (default: drop_oldest)
- `softcam_descramble_log_rate_limit_sec` (default: 5)

### 2) Пер-стрим (через input URL hash)

Можно передать напрямую в конфиг input (через `#...`), если это поддерживается вашим конфигом:
- `#descramble_parallel=per_stream_thread`
- `#descramble_batch_packets=64`
- `#descramble_queue_depth_batches=16`
- `#descramble_worker_stack_kb=256`
- `#descramble_drop_policy=drop_oldest`
- `#descramble_log_rate_limit_sec=5`

## Как проверить, что работает

1) Откройте Analyze / stats decrypt-модуля для канала с SoftCAM.
   В stats появится блок:
   - `descramble.mode = per_stream_thread`
   - `descramble.batches`, `descramble.decrypt_avg_us`, `descramble.in_queue_len/out_queue_len`, `descramble.drops`

2) На сервере проверьте, что появился дополнительный thread `descramble`:

```bash
PID=<stream_pid>
ps -T -p "$PID" -o pid,tid,psr,pcpu,comm | head
```

3) Снимите инцидент/до-после (per-core/per-thread):

```bash
PID=<stream_pid>
OUT=tools/perf/results/incident_$(date +%Y%m%d_%H%M%S)
tools/perf/capture_incident.sh "$PID" 15 "$OUT"
```

## Рекомендации по значениям

- Стартуйте с `batch_packets=64` и `queue_depth_batches=16`.
- Если нужен меньший latency (или канал низкого битрейта) — уменьшайте `batch_packets` до 16–32.
- Если наблюдаются drops — увеличьте `queue_depth_batches` (но это увеличит RAM).
