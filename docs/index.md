<div class="sh-landing" markdown="1">

<div class="sh-hero sh-bleed">
  <div class="sh-hero-inner">
    <div class="sh-hero-copy">
      <h1 class="sh-title">Stream Hub</h1>
      <p class="sh-lead">
        Управление вещанием в одном месте: входы, каналы, выходы, диагностика и API.
      </p>
      <div class="sh-cta">
        <a class="md-button md-button--primary" href="quick-start/">Начать за 5 минут</a>
        <a class="md-button" href="quick-start/check-playback/">Проверить статус</a>
        <a class="md-button" href="manual/troubleshooting/">Диагностика</a>
      </div>
      <div class="sh-hero-badges">
        <span class="sh-badge">Web UI + API</span>
        <span class="sh-badge">UDP / HTTP‑TS / HLS / DASH</span>
        <span class="sh-badge">Backup / failover / MPTS</span>
        <span class="sh-badge">Relay + Transcode (FULL)</span>
      </div>
      <div class="sh-hero-contacts" aria-label="Контакты">
        <a class="sh-hero-contact" href="https://t.me/streamhubfree" target="_blank" rel="noopener">Чат в Telegram</a>
        <span class="sh-hero-contact-sep" aria-hidden="true">•</span>
        <a class="sh-hero-contact" href="https://t.me/Serhiidevel" target="_blank" rel="noopener">Автор</a>
      </div>
      <div class="sh-hero-note">
        Open Source (GPLv3). Фокус проекта: стабильное вещание, понятный контроль и предсказуемая эксплуатация.
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

<h2>Запусти за 3 шага</h2>

<div class="sh-grid">
  <div class="sh-card" markdown="1">
    <h3>1. Установка</h3>
    <p><span class="sh-step-status is-ready">Готово</span></p>
    <p>Поставьте Stream Hub через installer под вашу ОС.</p>
    <p>Сразу получите бинарник, systemd-шаблон и базовую проверку окружения.</p>
    <p><a href="quick-start/installation/">Открыть шаг установки</a></p>
  </div>

  <div class="sh-card" markdown="1">
    <h3>2. Первый канал</h3>
    <p><span class="sh-step-status is-progress">Выполняется</span></p>
    <p>Создайте stream в Web UI: добавьте input и output, затем сохраните конфиг.</p>
    <p>Для старта достаточно одного входа и одного выхода.</p>
    <p><a href="quick-start/first-stream/">Открыть шаг создания канала</a></p>
  </div>

  <div class="sh-card" markdown="1">
    <h3>3. Проверка статуса</h3>
    <p><span class="sh-step-status is-attention">Нужно внимание</span></p>
    <p>Проверьте в Dashboard состояние канала: <code>online</code>, <code>bitrate</code>, <code>clients</code>.</p>
    <p class="sh-critical-step">Критично: если input в состоянии <code>OFFLINE</code>, выход не появится.</p>
    <p><a href="quick-start/check-playback/">Открыть шаг проверки</a></p>
  </div>
</div>

<div class="sh-onboarding-progress" aria-label="Прогресс онбординга">
  <div class="sh-progress-item is-done"><span>Установка</span></div>
  <div class="sh-progress-item is-active"><span>Первый канал</span></div>
  <div class="sh-progress-item is-alert"><span>Проверка и диагностика</span></div>
</div>

<h2>Схема потока</h2>

<div class="sh-pipeline" role="img" aria-label="Input переходит в Stream Hub и отправляется в Output">
  <div class="sh-pipeline-node">
    <div class="sh-pipeline-title">Input</div>
    <div class="sh-pipeline-text">UDP / HTTP-TS / HLS / DASH</div>
  </div>
  <div class="sh-pipeline-arrow" aria-hidden="true">→</div>
  <div class="sh-pipeline-node is-core">
    <div class="sh-pipeline-title">Stream Hub</div>
    <div class="sh-pipeline-text">Failover, Remap, MPTS, API, UI</div>
  </div>
  <div class="sh-pipeline-arrow" aria-hidden="true">→</div>
  <div class="sh-pipeline-node">
    <div class="sh-pipeline-title">Output</div>
    <div class="sh-pipeline-text">UDP / HTTP-TS / HLS</div>
  </div>
</div>

<h2>Что такое Stream Hub</h2>

<ul>
  <li><a href="about/what-is-stream-hub/">Что такое Stream Hub</a></li>
  <li><a href="about/stream-hub-iptv/">Stream Hub для IPTV</a></li>
  <li><a href="about/why-stream-hub/">Почему Stream Hub</a></li>
  <li><a href="about/stream-hub-web-ui/">Stream Hub Web UI</a></li>
  <li><a href="about/stream-hub-api/">Stream Hub API</a></li>
</ul>

<h2>Быстрая установка</h2>

```bash
curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- --mode binary --runtime-only
```

<p>Если нужен транскод: убедитесь, что у вас профиль <strong>FULL</strong> и доступен <code>ffmpeg</code>.</p>
<p>Подробнее: <a href="manual/build-profiles/">Build profiles (FULL/LITE)</a>.</p>

<h2>Что получите после установки</h2>

<ul>
  <li>Web UI для управления каналами и диагностики.</li>
  <li>API для автоматизации и интеграций.</li>
  <li>Базовый operational контур: логи, systemd, статус вещания.</li>
</ul>

<h2>Дальше</h2>

<div class="sh-next">
  <a class="md-button md-button--primary" href="quick-start/">Открыть быстрый старт</a>
  <a class="md-button" href="manual/">Открыть руководство</a>
</div>

</div>

<div class="sh-section">

<h2>Первый запуск вручную (опционально)</h2>

```bash
sudo mkdir -p /etc/stream
sudo sh -c 'echo {} > /etc/stream/prod.json'
sudo /usr/local/bin/stream -c /etc/stream/prod.json -p 9060
```

<p>Панель откроется здесь:</p>
<ul>
  <li><code>http://SERVER:9060</code></li>
</ul>

<div class="sh-next">
  <a class="md-button md-button--primary" href="quick-start/web-ui/">Перейти в Web UI</a>
  <a class="md-button" href="manual/troubleshooting/">Если не играет</a>
</div>

</div>

</div>
