# Settings (настройки сервера)

Settings — это общие настройки Stream Hub. Они влияют на весь инстанс.

## Как устроено

- Вкладки/разделы Settings находятся слева (General, Users, HLS, Buffer и т.д.).
- Большинство настроек можно менять “на лету”.
- Настройки, которые требуют перезапуска (если такие есть), лучше менять в окно обслуживания.

## Что чаще всего трогают

- **General**: интерфейс, Polling, performance‑флаги, Lua GC.
- **Users**: пользователи, права, сброс пароля.
- **Public URLs**: как формируются ссылки, которые видит пользователь.
- **HLS / HTTP Play**: параметры выдачи по HTTP.
- **HTTP Authentication**: защита Web UI/API.
- **Softcam / CAS**: CAM‑профили и связанные настройки (если используете).
- **Buffer / HLSSplitter**: отдельные сервисы и их лимиты.

## Быстрые ссылки

- [General](settings-general.md)
- [Users](settings-users.md)
- [Public URLs](settings-public-urls.md)
- [HLS](settings-hls.md)
- [HTTP Play](settings-http-play.md)
- [HTTP Authentication](settings-http-auth.md)
- [Buffer](settings-buffer.md)
- [Servers](settings-servers.md)
- [Groups](settings-groups.md)
- [Import](settings-import.md)
- [Edit Config / History / Restart / License](settings-config.md)

## Полезные проверки после изменений

1. Откройте **Dashboard** и убедитесь, что каналы не “провалились” в OFFLINE.
2. Проверьте 1–2 выхода (`/live`, `/hls` или UDP).
3. Посмотрите логи: нет ли ошибок сразу после Save.

!!! tip "Если вы не уверены"
    Меняйте по одному параметру и проверяйте результат. Так проще найти причину.
