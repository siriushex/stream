# Cesbo Stream API (HTTP): клиент

Stream Hub умеет **ходить в HTTP API Cesbo Stream**.
Это полезно, если у вас уже есть сервер Stream и вы хотите управлять им скриптами.

## Коротко

- База: `http://SERVER:8000` (без завершающего `/`)
- Авторизация: **Basic Auth** (логин/пароль администратора Stream)
- `GET /api/...` — чтение статусов/конфига
- `POST /control/` — управление (`{"cmd":"...", ...}`)
- Встроены таймауты и мягкие retry (1–3 попытки) при сетевых сбоях

!!! warning "Безопасность"
    Не передавайте пароль в открытых логах/скриптах.
    Не выставляйте API наружу без защиты.

## Как использовать в Lua-скриптах

Подключите клиент:

```lua
dofile("scripts/base.lua")
dofile("scripts/cesbo_api_client.lua")
```

Создайте клиента:

```lua
local client = assert(CesboApiClient.new({
  baseUrl = "http://127.0.0.1:8000",
  login = "admin",
  password = "admin",
  debug = true,
}))
```

Пример: system-status:

```lua
client:GetSystemStatus(1, function(ok, data, err)
  if not ok then
    log.error(err)
    return
  end
  log.info(json.encode_pretty(data))
end)
```

## CLI демо (готовый скрипт)

В репозитории есть демонстрационный CLI:

`scripts/cesbo_api_cli.lua`

### 1) Прочитать статус процесса

```bash
/usr/local/bin/stream scripts/cesbo_api_cli.lua \
  --base http://SERVER:8000 --login admin --password admin --status
```

### 2) Перезапустить конкретный поток

```bash
/usr/local/bin/stream scripts/cesbo_api_cli.lua \
  --base http://SERVER:8000 --login admin --password admin --restart-stream STREAM_ID
```

### 3) Посмотреть сессии и закрыть одну

```bash
/usr/local/bin/stream scripts/cesbo_api_cli.lua \
  --base http://SERVER:8000 --login admin --password admin --sessions
```

```bash
/usr/local/bin/stream scripts/cesbo_api_cli.lua \
  --base http://SERVER:8000 --login admin --password admin --close-session SESSION_ID
```

## Что реализовано

Клиент покрывает основные методы API Cesbo Stream:

- Process status: `GetSystemStatus()`, `RestartServer()`
- Adapters: `GetAdapterInfo()`, `SetAdapter()`, `RestartAdapter()`, `RemoveAdapter()`, `GetAdapterStatus()`
- Streams: `GetStreamInfo()`, `SetStream()`, `ToggleStream()`, `RestartStream()`, `SetStreamInput()`, `RemoveStream()`, `GetStreamStatus()`
- Config: `LoadConfiguration()`, `UploadConfiguration()`, `SetLicense()`, `SetStreamImage()`
- Scan: `ScanInit()`, `ScanKill()`, `ScanCheck()`
- Sessions: `GetSessions()`, `CloseSession()`
- Users: `GetUser()`, `SetUser()`, `RemoveUser()`, `ToggleUser()`

## Если не работает

Проверьте:

- URL правильный: `http://SERVER:8000`
- Basic Auth верный (логин/пароль администратора Stream)
- Сервер Stream отвечает на `/api/system-status` в браузере/через curl
- Нет firewall между Stream Hub и Stream
