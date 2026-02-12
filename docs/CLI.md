# Astral CLI

Бинарь: `astral` (или `astra` в legacy сборках).

## Основные режимы

### `--stream` (основной сервер)
Запуск сервера с UI/API.
```bash
astral --stream -p 8000 --config /path/to/config.json
```

### `--relay`
Релей потоков через HTTP (legacy режим Astra).
```bash
astral --relay
```

### `--analyze`
MPEG‑TS анализатор. Полезно для PID/битрейта/PSI.
```bash
astral --analyze -n 1 udp://239.1.1.1:1234
```

### `--dvbls`
Список DVB‑адаптеров (busy/free).
```bash
astral --dvbls
```

### `--femon`
DVB монитор (signal/SNR/lock).
```bash
astral --femon dvb://#adapter=0&type=S2&tp=...
```

## Настройки сервера
Опции server.lua:
```text
  -a ADDR             listen address (default: 0.0.0.0)
  -p PORT             listen port (default: 8000)
  --data-dir PATH     data directory (default: ./data or <config>.data)
  --db PATH           sqlite db path (default: data-dir/astra.db)
  --web-dir PATH      web ui directory (default: ./web)
  --hls-dir PATH      hls output directory (default: data-dir/hls)
  --hls-route PATH    hls url prefix (default: /hls)
  --stream-shard S/C  run only a shard of streams (example: 0/4)
  -c PATH             alias for --config
  -pass               reset admin password to default (admin/admin)
  --config PATH       import config (.json or .lua) before start
  --import PATH       legacy alias for --config (json)
  --import-mode MODE  import mode: merge or replace (default: merge)
```

## Примеры многопроцессного запуска
```bash
astral /etc/astral/a.json -p 9060
astral /etc/astral/b.json -p 9061
```

## Примечания
- Для HTTPS‑входов может потребоваться дополнительный обработчик (см. docs по HTTP input).
- В AI‑контексте CLI вызывается только **по запросу**, с таймаутом и кешем.
- Для CLI‑контекста рекомендуется наличие `timeout` в системе (иначе CLI будет пропущен по умолчанию).
