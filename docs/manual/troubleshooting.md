# Если не работает

## Web UI не открывается

Проверьте, что порт слушается:

```bash
ss -lntp | grep ':9060' || true
```

Проверьте логи:

```bash
journalctl -u stream@prod.service -n 200 --no-pager
```

## Канал OFFLINE / битрейт 0

- Проверьте Input (адрес, интерфейс, доступ).
- Для multicast часто проблема в сети.

## Выход включён, но не играет

- Сначала вход: ONLINE и битрейт не 0.
- Потом firewall и сеть.

### HTTP‑TS (`/live/...`) не играет

- Проверьте, что URL без “.ts”: `/live/STREAM_ID`
- Проверьте, что порт доступен с вашей машины.
- Попробуйте `curl -I`:

```bash
curl -I "http://SERVER:9060/live/STREAM_ID"
```

### HLS не играет

- Проверьте, что плейлист открывается:

```bash
curl -I "http://SERVER:9060/hls/STREAM_ID/index.m3u8"
```

- Если сегменты на диске — проверьте место.

## Посмотреть логи

```bash
journalctl -u stream@prod.service -f
```
