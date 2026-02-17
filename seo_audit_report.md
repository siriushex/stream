# SEO Audit Report: stream.centv.ru

## 1) Карта ключевых страниц

- `/` — главная (оффер, быстрый вход, CTA).
- `/about/what-is-stream-hub/` — что такое Stream Hub.
- `/about/stream-hub-iptv/` — SEO-целевая страница для IPTV intent.
- `/about/why-stream-hub/` — ценностное сравнение/позиционирование.
- `/about/stream-hub-web-ui/` — SEO-страница под intent `Stream Hub Web UI`.
- `/about/stream-hub-api/` — SEO-страница под intent `Stream Hub API`.
- `/quick-start/` — общий старт.
- `/quick-start/installation/` — установка.
- `/quick-start/run/` — запуск.
- `/quick-start/web-ui/` — вход в UI.
- `/quick-start/first-stream/` — первый stream.
- `/quick-start/check-playback/` — проверка воспроизведения.
- `/quick-start/run-as-service/` — systemd.
- `/manual/troubleshooting/` — диагностика.
- `/faq/` — FAQ с FAQ Schema.
- `/changelog/` — версии/изменения.

## 2) Целевые запросы (RU + EN)

### Брендовые

- `stream hub`
- `stream hub установка`
- `stream hub web ui`
- `stream hub api`
- `stream hub faq`
- `stream hub changelog`
- `stream hub troubleshooting`

### Отраслевые/технические

- `iptv stream relay`
- `udp relay server`
- `hls http-ts relay`
- `iptv monitoring bitrate`
- `stream management web ui`
- `dash input relay`
- `backup input failover`

### Сравнительные (вторичный контекст)

- `stream hub vs flussonic`
- `flussonic alternative open source`
- `astra-like stream management`
- `astra compatibility stream hub`

Принцип: бренд в приоритете (`Stream Hub`), Astra/Flussonic только в нейтральном контексте сценариев/наследия.

## 3) Технический SEO-аудит

### До правок (ключевые проблемы)

- Нет системных page-level SEO title/description на ключевых страницах.
- Не было OG/Twitter метаданных.
- Не было отдельной SEO-архитектуры под брендовые intent-страницы.
- В docs были legacy `manual/*.html` (риск дублей контента).
- Не было `robots.txt`.

### После правок

- Добавлены page-level SEO title + description + OG + Twitter через шаблон `overrides/main.html`.
- Canonical присутствует на ключевых страницах (через `site_url` + шаблон).
- `robots.txt` добавлен, `sitemap.xml` присутствует.
- FAQ Schema (`FAQPage`) добавлена в `/faq/`.
- По внутренним ссылкам: `missing_count=0` (исключая бинарные download endpoints `/stream`, `install*.sh`, `stream-src.tar.gz`).
- Дубли из `manual/*.html` исключены из сборки (`exclude_docs: manual/*.html`).

## 4) Контент и тон

### Наблюдения

- Бренд Stream Hub теперь доминирует в SEO title/description.
- Терминология унифицирована: `stream`, `input`, `output`, `transcode`, `bitrate`, `relay`, `UDP/HTTP-TS/HLS/DASH`, `auth`, `monitoring`.
- Добавлены сценарные мосты: установка -> запуск -> проверка -> диагностика.
- Сравнительные формулировки по Astra/Flussonic нейтральные, без агрессивных claims.

## 5) Риски переформулировок

- Риск 1: переобещание “полной совместимости” с Astra/Flussonic.
  - Митигация: прямой текст о том, что это контекст сценариев, а не claim полной идентичности.
- Риск 2: keyword stuffing в RU/EN миксе.
  - Митигация: 1 главный intent на страницу + ограниченный набор вторичных фраз.
- Риск 3: просадка UX из-за эффектов.
  - Митигация: убраны тяжёлые motion-эффекты, оставлены только полезные micro-interactions.

## 6) Матрица проблем и приоритетов

| Локальность | Проблема | Приоритет | План правки |
|---|---|---|---|
| Глобально (template) | Нет page-level SEO метаданных | P0 | Добавить custom template override с SEO map по ключевым страницам |
| IA сайта | Нет брендовых SEO-страниц под intent | P0 | Добавить `/about/what-is-stream-hub/`, `/about/stream-hub-iptv/`, `/about/why-stream-hub/` |
| FAQ | Недостаточный SEO intent coverage | P1 | Добавить поисковые вопросы + FAQ Schema |
| Docs build | Риск дублей `manual/*.html` | P1 | Исключить `manual/*.html` из публикации |
| Robots | Отсутствовал robots.txt | P1 | Добавить `docs/robots.txt` с `Sitemap` |
| Главная | Нехватка SEO/UX CTA пути | P1 | Добавить CTA: “Начать за 5 минут”, “Проверить статус”, “Диагностика” |
| UX scripts | Избыточные motion-эффекты | P2 | Упростить JS/CSS эффекты без потери полезных feedback |
