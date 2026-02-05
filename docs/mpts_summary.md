# MPTS Summary (Astral)

Краткая сводка реализации MPTS и проверок.

## Что реализовано
- Полноценный MPTS mux с PAT/PMT/SDT/NIT/TDT/TOT (CAT пустой или pass‑through).
- Auto-remap PID по умолчанию; строгий режим при `disable_auto_remap=true`.
- CBR с null stuffing по `advanced.target_bitrate`.
- `strict_pnr` и `spts_only` для контроля multi‑PAT.
- PCR restamp + EWMA‑сглаживание (`pcr_smoothing`).
- Pass‑through EIT/CAT из выбранного источника.
- LCN tag configurable (`nit.lcn_descriptor_tag`).
- Экспорт MPTS метрик (bitrate/null%/PSI interval) в статус и Prometheus.
- UI для параметров MPTS + массовые операции по сервисам.

## Ограничения
- Delivery поддерживается только DVB‑C.
- `advanced.si_interval_ms` < 50 игнорируется.
- `advanced.target_bitrate <= 0` отключает CBR (игнорируется).
- `mpts_config.nit.lcn_version` действует как alias для `advanced.nit_version` (если он не задан).

## Быстрая проверка
```bash
./tools/verify_mpts.sh "udp://127.0.0.1:12346"
EXPECT_TOT=1 EXPECT_PNRS="101,102" EXPECT_PMT_PNRS="101,102" ./tools/verify_mpts.sh "udp://127.0.0.1:12346"
EXPECT_LOG="NIT: network_id: 1" ./tools/verify_mpts.sh "udp://127.0.0.1:12346"
```

## CI smoke
```bash
contrib/ci/smoke_mpts.sh
MPTS_STRICT_PNR_SMOKE=1 contrib/ci/smoke.sh
contrib/ci/smoke_mpts_pid_collision.sh
contrib/ci/smoke_mpts_pass_tables.sh
```
