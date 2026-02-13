# FAQ

## Нужен ли ffmpeg?

Только если вы включаете транскодирование.

## Где лежат конфиги?

Обычно в `/etc/stream`.

## Как сбросить пароль администратора?

```bash
sudo /usr/local/bin/stream --reset-password
```

## Как запустить несколько инстансов?

Удобнее через systemd‑шаблон:

```bash
sudo /usr/local/bin/stream --init
sudo systemctl enable --now stream@prod.service
```

