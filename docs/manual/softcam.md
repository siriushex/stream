# SoftCAM / CAS

Этот раздел нужен, если ваш входной поток зашифрован и его нужно descramble на сервере.

Важно:

- Stream Hub **не** “добывает ключи”. Он использует уже настроенный CAM/CAS профиль.
- Здесь только про то, **как подключить** CAM к каналу и как сделать работу стабильнее.

## Где настраивается CAM

Обычно CAM‑профили добавляются в:

- **Settings → Softcam**
- **Settings → CAS**

Там вы создаёте CAM с ID (например `sh`), а потом используете этот ID в входном URL.

## Как привязать CAM к входу

В конец input URL добавьте `#cam=<id>`.

Пример:

```text
udp://239.0.0.1:1234#cam=sh
```

## CAM backup (primary + backup)

Если у вас есть два CAM, можно указать резерв:

```text
udp://239.0.0.1:1234#cam=sh&cam_backup=sh_4
```

Дополнительные параметры (если они включены в вашей сборке):

- `cam_backup_mode=race|hedge|failover`
- `cam_backup_hedge_ms=0..500`
- `cam_prefer_primary_ms=0..500`

Рекомендованный стартовый вариант (обычно самый предсказуемый):

```text
udp://239.0.0.1:1234#cam=sh&cam_backup=sh_4&cam_backup_mode=hedge&cam_backup_hedge_ms=80&cam_prefer_primary_ms=30
```

## Производительность: parallel descramble

Если при SoftCAM одно ядро CPU забивается в 100% и появляются “рывки”,
можно включить распараллеливание descramble:

- **Settings → General → SoftCAM descramble parallel**
- значение: `per_stream_thread`

Это выносит тяжёлую часть descramble в отдельный поток на канал/инстанс.

!!! tip "Как проверить эффект"
    Смотрите нагрузку по ядрам (`mpstat -P ALL 1`) и качество TS (CC/PES ошибки) до/после.

