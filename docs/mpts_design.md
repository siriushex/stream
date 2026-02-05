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
      "network_search": "mux_a,mux_b"
    },
    "advanced": {
      "si_interval_ms": 500,
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
- TDT/TOT: UTC время; TOT с local_time_offset_descriptor при задании country/utc_offset
- CAT: генерируется пустой (без CA descriptors)
- EIT: выключен по умолчанию; pass‑through при `pass_eit` (только для single input)

## CBR режим
- `advanced.target_bitrate` (бит/с)
- При недостаточном входном битрейте вставляются null‑пакеты (PID 0x1FFF)
- При превышении входного битрейта логируется предупреждение

## Auto‑remap
- По умолчанию включён.
- При `disable_auto_remap=true` — строгая проверка конфликтов, без замены PID.

## Ограничения
- Для стабильной работы каждый input рекомендуется как SPTS.
- EIT/CAT pass‑through корректен только при 1 сервисе (иначе возможны коллизии).
- `nit.network_search` принимает список `tsid` или `tsid:onid` через запятую и добавляет их в NIT.

## Быстрая проверка
```bash
./tools/verify_mpts.sh "udp://127.0.0.1:12346"
EXPECT_TOT=1 ./tools/verify_mpts.sh "udp://127.0.0.1:12346"
```
`EXPECT_TOT=1` нужен, если указан `country` и ожидается TOT.
