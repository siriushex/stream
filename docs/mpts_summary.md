# MPTS Summary (Astral)

Краткая сводка реализации MPTS и проверок.

## Что реализовано
- Полноценный MPTS mux с PAT/PMT/SDT/NIT/TDT/TOT и CAT (пустой по умолчанию, CA_descriptors из `mpts_config.ca`, либо pass‑through при `pass_cat`).
- TOT можно отключить отдельно (`advanced.disable_tot`), а DST задать явно (`general.dst.time_of_change/next_offset_minutes`).
- Auto-remap PID по умолчанию; строгий режим при `disable_auto_remap=true`.
- CBR с null stuffing по `advanced.target_bitrate`.
- `strict_pnr` и `spts_only` для контроля multi‑PAT.
- PCR restamp + EWMA‑сглаживание (`pcr_smoothing`).
- Pass‑through EIT/CAT из выбранного источника + фильтр EIT по `table_id` (`advanced.eit_table_ids`).
- LCN tags configurable (`nit.lcn_descriptor_tag` / `nit.lcn_descriptor_tags`).
- Экспорт MPTS метрик (bitrate/null%/PSI interval) в статус и Prometheus.
- UI для параметров MPTS + массовые операции по сервисам + быстрые инструменты “Convert inputs” / “Add from streams”.
- Auto-probe сервисов из UDP/RTP входа при пустом `mpts_services` (`advanced.auto_probe`).

## Ограничения
- Delivery поддерживается для DVB‑C/DVB‑T/DVB‑S (NIT delivery descriptor).
- `general.codepage` поддерживает ограниченный набор DVB charset marker: `utf-8`, `iso-8859-1` (default), `iso-8859-2/4/5/7/8/9`.
- `advanced.si_interval_ms` < 50 игнорируется.
- `advanced.target_bitrate <= 0` отключает CBR (игнорируется).
- `mpts_config.nit.lcn_version` действует как alias для `advanced.nit_version` (если он не задан).
- Повторяющиеся `mpts_services[].input` используют общий сокет.
- `advanced.auto_probe` работает только для UDP/RTP; `timeout` желателен, но не обязателен.

## Быстрая проверка
```bash
./tools/verify_mpts.sh "udp://127.0.0.1:12346"
EXPECT_TOT=1 EXPECT_PNRS="101,102" EXPECT_PMT_PNRS="101,102" ./tools/verify_mpts.sh "udp://127.0.0.1:12346"
EXPECT_LOG="NIT: network_id: 1" ./tools/verify_mpts.sh "udp://127.0.0.1:12346"
```

## Auto-split helper
```bash
python3 tools/mpts_pat_scan.py --addr 239.1.1.1 --port 1234 --duration 3 \\
  --input "udp://239.1.1.1:1234" --pretty
```
UI “Probe input” использует `/api/v1/mpts/scan` и возвращает список сервисов для UDP/RTP.

## CI smoke
```bash
contrib/ci/smoke_mpts.sh
MPTS_STRICT_PNR_SMOKE=1 contrib/ci/smoke.sh
contrib/ci/smoke_mpts_pid_collision.sh
contrib/ci/smoke_mpts_pass_tables.sh
contrib/ci/smoke_mpts_spts_only.sh
contrib/ci/smoke_mpts_auto_probe.sh
```
