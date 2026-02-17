# SEO Changes Summary

## 1) Оптимизированные страницы

| Страница | Основной ключ | Вторичные ключи |
|---|---|---|
| `/` | `stream hub` | `iptv relay`, `stream management`, `web ui`, `monitoring` |
| `/about/what-is-stream-hub/` | `что такое stream hub` | `stream hub платформа`, `iptv/ott`, `relay`, `api` |
| `/about/stream-hub-iptv/` | `stream hub iptv` | `iptv stream relay`, `udp relay server`, `hls http-ts`, `backup input` |
| `/about/why-stream-hub/` | `почему stream hub` | `stream hub vs flussonic`, `astra-like`, `stream stability`, `web ui api` |
| `/about/stream-hub-web-ui/` | `stream hub web ui` | `iptv web panel`, `stream monitoring`, `online bitrate`, `operator dashboard` |
| `/about/stream-hub-api/` | `stream hub api` | `stream automation api`, `iptv api control`, `monitoring integration`, `stream management api` |
| `/about/stream-hub-monitoring/` | `stream hub monitoring` | `bitrate monitoring`, `stream uptime`, `iptv monitoring`, `error diagnostics` |
| `/quick-start/` | `быстрый старт stream hub` | `stream hub install`, `first stream`, `online bitrate` |
| `/quick-start/installation/` | `установка stream hub` | `install stream hub`, `ubuntu centos`, `full lite`, `secure install` |
| `/quick-start/run/` | `запуск stream hub` | `stream hub web ui`, `stream hub api`, `port check`, `first run` |
| `/quick-start/first-stream/` | `первый канал stream hub` | `input output`, `stream online`, `iptv stream setup` |
| `/quick-start/check-playback/` | `проверка потока stream hub` | `http-ts`, `hls`, `udp`, `ffplay` |
| `/faq/` | `faq stream hub` | `stream hub troubleshooting`, `flussonic alternative`, `astra compatibility` |
| `/manual/troubleshooting/` | `диагностика stream hub` | `stream not playing`, `bitrate 0`, `input offline`, `auth/network` |
| `/changelog/` | `stream hub changelog` | `stream hub version`, `release notes`, `install scripts` |

## 2) Структурные изменения

- Добавлен новый раздел в nav: `О Stream Hub`.
- Добавлены 3 SEO-страницы:
  - `docs/about/what-is-stream-hub.md`
  - `docs/about/stream-hub-iptv.md`
  - `docs/about/why-stream-hub.md`

## 3) Технические SEO изменения

- `mkdocs.yml`:
  - добавлены `site_description`, `site_author`;
  - добавлен `theme.custom_dir: overrides`;
  - исключены `manual/*.html` (снижение риска дублей);
  - добавлен hook post-build для исключения `/admin/` из sitemap.
- `overrides/main.html`:
  - page-level SEO title/description;
  - OG/Twitter metadata + `og:image`;
  - `noindex` для страницы admin.
  - canonical сохранён.
- `docs/robots.txt`:
  - `Allow: /`
  - `Disallow: /admin/`, `Disallow: /admin/api/`
  - `Sitemap: https://stream.centv.ru/sitemap.xml`

## 4) Контент и UX

- Главная: усилены брендовые CTA и сценарный вход.
- FAQ: добавлены поисковые вопросы + JSON-LD FAQ Schema.
- Troubleshooting: сохранён быстрый диагностический путь.
- Упрощены тяжёлые motion-эффекты:
  - `docs/javascripts/extra.js`
  - `docs/stylesheets/extra.css`

## 5) Влияние на бренд-позиционирование

- Stream Hub зафиксирован как основной бренд в заголовках/meta.
- Astra/Flussonic упоминаются только как контекст сценариев/совместимости.
- Устранён риск смещения брендового трафика в сторону чужих имён.
