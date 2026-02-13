---
hide:
  - navigation
  - toc
---

<div class="sh-landing" markdown="1">

<div class="sh-hero sh-bleed">
  <div class="sh-hero-inner">
    <div class="sh-hero-copy">
      <h1 class="sh-title">Stream Hub</h1>
      <p class="sh-lead">
        Панель для потоков. Вставили вход. Включили выход. Проверили в плеере.
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
    </div>
    <div class="sh-hero-art" aria-hidden="true">
      <svg viewBox="0 0 720 480" class="sh-hero-svg" role="img" aria-label="">
        <defs>
          <linearGradient id="shg" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stop-color="currentColor" stop-opacity="0.18"/>
            <stop offset="100%" stop-color="currentColor" stop-opacity="0.02"/>
          </linearGradient>
          <filter id="shb" x="-30%" y="-30%" width="160%" height="160%">
            <feGaussianBlur stdDeviation="10"/>
          </filter>
        </defs>
        <rect x="0" y="0" width="720" height="480" rx="28" fill="url(#shg)"/>
        <g fill="none" stroke="currentColor" stroke-opacity="0.18" stroke-width="2">
          <path d="M120 140 C210 120, 250 170, 330 190" />
          <path d="M120 240 C210 220, 250 270, 330 290" />
          <path d="M120 340 C210 320, 250 370, 330 390" />
          <path d="M390 240 C470 210, 520 230, 600 200" />
          <path d="M390 240 C470 260, 520 280, 600 300" />
        </g>
        <g filter="url(#shb)">
          <circle cx="360" cy="240" r="34" fill="currentColor" fill-opacity="0.16"/>
          <circle cx="120" cy="140" r="18" fill="currentColor" fill-opacity="0.10"/>
          <circle cx="120" cy="240" r="18" fill="currentColor" fill-opacity="0.10"/>
          <circle cx="120" cy="340" r="18" fill="currentColor" fill-opacity="0.10"/>
          <circle cx="600" cy="200" r="18" fill="currentColor" fill-opacity="0.10"/>
          <circle cx="600" cy="300" r="18" fill="currentColor" fill-opacity="0.10"/>
        </g>
        <g fill="currentColor" fill-opacity="0.55">
          <circle cx="360" cy="240" r="10"/>
          <circle cx="120" cy="140" r="6"/>
          <circle cx="120" cy="240" r="6"/>
          <circle cx="120" cy="340" r="6"/>
          <circle cx="600" cy="200" r="6"/>
          <circle cx="600" cy="300" r="6"/>
        </g>
      </svg>
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
