# MPTS Design (Astral)

## Цель
Реализовать нативный MPTS‑режим для DVB‑C/QAM с корректными PSI/SI таблицами,
уникальными PID/PNR и режимом CBR с null‑пакетами.

## Конфигурация (JSON)
На уровне stream (input поддерживает `udp://...` и внутренний `stream://<id|name>`):
```json
{
  "id": "mux_1",
  "name": "DVB-C MPTS",
  "mpts": true,
  "mpts_services": [
    {
      "input": "udp://239.1.1.1:1234",
      "service_name": "News",
      "service_provider": "Provider",
      "service_type_id": 1,
      "lcn": 101,
      "pnr": 101,
      "scrambled": false
    }
  ],
  "mpts_config": {
    "general": {
      "network_id": 1,
      "network_name": "My Network",
      "provider_name": "Provider",
      "codepage": "utf-8",
      "tsid": 1,
      "onid": 1,
      "country": "RUS",
      "utc_offset": 3
    },
    "nit": {
      "delivery": "cable",
      "frequency": 650000,
      "symbolrate": 6875,
      "modulation": "256QAM",
      "fec": "auto",
      "network_search": "2:1,3:1"
    },
    "advanced": {
      "si_interval_ms": 500,
      "pcr_restamp": false,
      "strict_pnr": false,
      "pat_version": 0,
      "nit_version": 0,
      "cat_version": 0,
      "sdt_version": 0,
      "pass_nit": false,
      "pass_sdt": false,
      "pass_eit": false,
      "pass_tdt": false,
      "disable_auto_remap": false,
      "target_bitrate": 50000000
    }
  },
  "output": [
    "udp://239.9.9.9:1234?pkt_size=1316"
  ]
}
```

## Резервированные PID
- `0x0000` — PAT
- `0x0001` — CAT (опционально)
- `0x0010` — NIT
- `0x0011` — SDT/BAT
- `0x0012` — EIT
- `0x0014` — TDT/TOT
- `0x1FFF` — NULL

## Назначение PID и PNR
- PNR для каждого сервиса должен быть уникальным.
- PMT PID назначается автоматически, если `disable_auto_remap=false`.
- ES PID назначаются автоматически, если `disable_auto_remap=false`.
- При выключенном auto‑remap выполняется проверка конфликтов PID.

## PSI/SI генерация
- PAT: все program_number → PMT PID
- PMT: корректные PCR_PID и ES PID после ремапа
- SDT (Actual): service_descriptor (service_type/provider/name), free_CA_mode
- NIT (Actual): network_name + service_list + delivery descriptor (DVB‑C; другие delivery пока не применяются)
- LCN: если задан `mpts_services[].lcn`, добавляется logical_channel_descriptor (0x83) в NIT
- TDT/TOT: UTC время; TOT с local_time_offset_descriptor при задании country/utc_offset
- CAT: генерируется пустой (без CA descriptors)
- EIT: выключен по умолчанию; pass‑through при `pass_eit` (только для single input)

## CBR режим
- `advanced.target_bitrate` (бит/с)
- При недостаточном входном битрейте вставляются null‑пакеты (PID 0x1FFF)
- При превышении входного битрейта логируется предупреждение

## PCR restamp
- `advanced.pcr_restamp` (bool) — переписывает PCR по локальному времени выхода.
- Полезно для выравнивания PCR при нестабильных/рвущихся входах.

## Auto‑remap
- По умолчанию включён.
- При `disable_auto_remap=true` — строгая проверка конфликтов, без замены PID.
- При включённом auto‑remap PID назначаются последовательно, начиная с `0x0020`
  (зарезервированные PID остаются свободными).

## Ограничения
- Для стабильной работы каждый input рекомендуется как SPTS.
- EIT/CAT pass‑through корректен только при 1 сервисе (иначе возможны коллизии).
- `nit.network_search` принимает список `tsid` или `tsid:onid` через запятую и добавляет их в NIT.
- `mpts_services[].lcn` допускает значения 1..1023 (0 игнорируется).
- `mpts_config.nit.lcn_version` не поддерживается и игнорируется.
- `general.codepage` поддерживает только UTF-8 (маркер 0x15 в дескрипторах).
- `mpts_services[].service_type_id` допускает значения 1..255 (пусто = 1).
- `advanced.strict_pnr=true` запрещает использовать входные PAT с несколькими программами без явного `pnr`.
- `advanced.si_interval_ms` меньше 50 игнорируется.
- `advanced.target_bitrate <= 0` отключает CBR (значение игнорируется).

## Быстрая проверка
```bash
./tools/verify_mpts.sh "udp://127.0.0.1:12346"
EXPECT_TOT=1 EXPECT_PNRS="101,102" EXPECT_PMT_PNRS="101,102" ./tools/verify_mpts.sh "udp://127.0.0.1:12346"
EXPECT_TOT=1 EXPECT_NIT_TS_LIST="1:1,2:1,3:1" EXPECT_PMT_ES_PIDS="101=256;102=256" ./tools/verify_mpts.sh "udp://127.0.0.1:12346"
# Проверка наличия сообщений в анализаторе:
EXPECT_LOG="NIT: network_id: 1" ./tools/verify_mpts.sh "udp://127.0.0.1:12346"
```
`EXPECT_TOT=1` нужен, если указан `country` и ожидается TOT.

## CI smoke
Для быстрых проверок доступны скрипты в `contrib/ci`:
- `contrib/ci/smoke_mpts.sh` — базовый MPTS smoke.
- `contrib/ci/smoke_mpts_strict_pnr.sh` — проверка `strict_pnr` (multi‑PAT без PNR).
- `contrib/ci/smoke.sh` поддерживает опцию `MPTS_STRICT_PNR_SMOKE=1`.

## Acceptance checklist
- [x] MPTS мультиплексирует 2+ сервиса в один TS (PAT/PMT/SDT/NIT/TDT/TOT).
- [x] PID/PNR уникальны, auto-remap по умолчанию.
- [x] Настройки network_id/network_name/tsid/onid/service/provider применяются.
- [x] DVB-C delivery (frequency/symbolrate/modulation/fec) в NIT.
- [x] CBR с null stuffing (target_bitrate).
- [x] UI отражает доступные параметры и предупреждает о конфликтных режимах.
- [x] Polling/обновления статусов не сбрасывают состояние MPTS.
- [x] Документация и smoke-скрипты доступны.
