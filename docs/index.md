---
hide:
  - toc
---

<div class="sh-landing" markdown="1">

<div class="sh-hero sh-bleed">
  <div class="sh-hero-inner">
    <div class="sh-hero-copy">
      <h1 class="sh-title">Stream Hub</h1>
      <p class="sh-lead">
        Центр управления стримами: конфигурация, запуск, диагностика, API-доступ.
      </p>
      <div class="sh-cta">
        <a class="md-button md-button--primary" href="quick-start/">Быстрый старт</a>
        <a class="md-button" href="manual/">Руководство</a>
        <a class="md-button" href="https://stream.centv.ru/stream">Скачать</a>
      </div>
      <div class="sh-hero-badges">
        <span class="sh-badge">Web UI + API</span>
        <span class="sh-badge">UDP / HTTP‑TS / HLS</span>
        <span class="sh-badge">Транскодирование: по желанию</span>
      </div>
      <div class="sh-hero-contacts" aria-label="Контакты">
        <a class="sh-hero-contact" href="https://t.me/streamhubfree" target="_blank" rel="noopener">Чат в Telegram</a>
        <span class="sh-hero-contact-sep" aria-hidden="true">•</span>
        <a class="sh-hero-contact" href="https://t.me/Serhiidevel" target="_blank" rel="noopener">Автор</a>
      </div>
    </div>
    <div class="sh-hero-art" aria-hidden="true">
      <svg viewBox="0 0 720 480" class="sh-hero-wires-svg" aria-hidden="true">
        <defs>
          <linearGradient id="shWireG" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stop-color="#0066ff" stop-opacity="0.55"/>
            <stop offset="100%" stop-color="#10b981" stop-opacity="0.55"/>
          </linearGradient>
          <filter id="shWireBlur" x="-30%" y="-30%" width="160%" height="160%">
            <feGaussianBlur stdDeviation="6"/>
          </filter>
        </defs>

        <g class="sh-hero-wires" fill="none" stroke="url(#shWireG)" stroke-opacity="0.30" stroke-width="3" stroke-linecap="round">
          <path d="M150 150 C260 118, 270 186, 336 210" />
          <path d="M150 240 C252 214, 270 270, 336 286" />
          <path d="M150 330 C252 306, 276 364, 336 376" />
          <path d="M384 240 C472 205, 526 224, 610 200" />
          <path d="M384 240 C472 270, 526 290, 610 302" />
        </g>

        <g class="sh-hero-hub" filter="url(#shWireBlur)" opacity="0.65">
          <circle cx="360" cy="240" r="54" fill="url(#shWireG)" fill-opacity="0.18"/>
        </g>

        <g class="sh-hero-nodes" fill="url(#shWireG)" opacity="0.68">
          <circle cx="150" cy="150" r="6"/>
          <circle cx="150" cy="240" r="6"/>
          <circle cx="150" cy="330" r="6"/>
          <circle cx="610" cy="200" r="6"/>
          <circle cx="610" cy="302" r="6"/>
        </g>
      </svg>
      <img class="sh-hero-logo" src="assets/logo.svg" alt="" loading="eager">
    </div>
  </div>
</div>

<div class="sh-section">

## Установка

<div class="sh-grid">
  <div class="sh-card" markdown="1">
    <h3>Ubuntu / Debian</h3>

```bash
curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- --mode binary --runtime-only
```

<div class="sh-muted" markdown="1">
Если бинарник не подошёл (старая система или не хватает библиотек), поставьте из исходников:

```bash
curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- --mode source
```
</div>
  </div>

  <div class="sh-card" markdown="1">
    <h3>CentOS / Rocky / Alma / RHEL</h3>

```bash
curl -fsSL https://stream.centv.ru/install-centos.sh | sudo bash
```

<div class="sh-muted" markdown="1">
Если `curl` ругается на сертификат, используйте HTTP для запуска установщика:

```bash
curl -fsSL http://stream.centv.ru/install-centos.sh | sudo bash
```
</div>
  </div>

  <div class="sh-card" markdown="1">
    <h3>macOS</h3>

```bash
curl -fsSL https://stream.centv.ru/install-macos.sh | bash
```

<div class="sh-muted">
Транскодирование на macOS — отдельная история. Если оно нужно, ставьте ffmpeg (например через Homebrew).
</div>
  </div>
</div>

## Первый запуск

```bash
sudo mkdir -p /etc/stream
sudo sh -c 'echo {} > /etc/stream/prod.json'

sudo /usr/local/bin/stream -c /etc/stream/prod.json -p 9060
```

Панель откроется здесь:

- `http://SERVER:9060`

<div class="sh-next">
  <a class="md-button md-button--primary" href="quick-start/">Продолжить: быстрый старт</a>
  <a class="md-button" href="manual/">Открыть руководство</a>
</div>

</div>

</div>
