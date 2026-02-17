# Changelog

## Быстрые ссылки на версии

### Бинарники и install scripts (актуальные)

- **FULL (latest)**: [https://stream.centv.ru/stream](https://stream.centv.ru/stream)
- **LITE (no transcode, latest)**: [https://stream.centv.ru/stream-linux-x86_64-lite](https://stream.centv.ru/stream-linux-x86_64-lite)
- **Installer Linux**: [https://stream.centv.ru/install.sh](https://stream.centv.ru/install.sh)
- **Installer CentOS**: [https://stream.centv.ru/install-centos.sh](https://stream.centv.ru/install-centos.sh)
- **Installer macOS**: [https://stream.centv.ru/install-macos.sh](https://stream.centv.ru/install-macos.sh)
- **Source tarball (latest)**: [https://stream.centv.ru/stream-src.tar.gz](https://stream.centv.ru/stream-src.tar.gz)

### Снимки исходников по ревизиям (GitHub)

> В репозитории пока нет оформленных `tags/releases`, поэтому для разных версий используем ссылки на конкретные коммиты.

- **2026-02-17** `627c306` (docs pass): [commit](https://github.com/siriushex/stream/commit/627c306), [tar.gz](https://github.com/siriushex/stream/archive/627c306.tar.gz)
- **2026-02-17** `fef5e0b` (SEO monitoring page): [commit](https://github.com/siriushex/stream/commit/fef5e0b), [tar.gz](https://github.com/siriushex/stream/archive/fef5e0b.tar.gz)
- **2026-02-17** `a26e38b` (SEO indexation hardening): [commit](https://github.com/siriushex/stream/commit/a26e38b), [tar.gz](https://github.com/siriushex/stream/archive/a26e38b.tar.gz)
- **2026-02-17** `f2a3685` (SEO web-ui/api pages + CI checks): [commit](https://github.com/siriushex/stream/commit/f2a3685), [tar.gz](https://github.com/siriushex/stream/archive/f2a3685.tar.gz)
- **2026-02-17** `a78d4ca` (SEO/docs optimization): [commit](https://github.com/siriushex/stream/commit/a78d4ca), [tar.gz](https://github.com/siriushex/stream/archive/a78d4ca.tar.gz)
- **2026-02-17** `d617cb8` (settings no-op save): [commit](https://github.com/siriushex/stream/commit/d617cb8), [tar.gz](https://github.com/siriushex/stream/archive/d617cb8.tar.gz)
- **2026-02-17** `971bb64` (DASH + remote API + stability): [commit](https://github.com/siriushex/stream/commit/971bb64), [tar.gz](https://github.com/siriushex/stream/archive/971bb64.tar.gz)
- **2026-02-16** `6950fcd` (CentOS deps bundle/perf): [commit](https://github.com/siriushex/stream/commit/6950fcd), [tar.gz](https://github.com/siriushex/stream/archive/6950fcd.tar.gz)

Полная история изменений: [CHANGELOG.md в GitHub](https://github.com/siriushex/stream/blob/main/CHANGELOG.md)

## 2026-02-17

### Что изменилось

- Устойчивость API/UI:
  - ускорено сохранение настроек без фактических изменений (`no-op save`),
  - стабилизирован список stream при большом количестве элементов,
  - усилены базовые ограничения публичного API.
- Функциональность:
  - добавлен DASH input в основной поток работ,
  - расширено удалённое управление серверами по API,
  - polling по умолчанию приведён к 1 секунде (оперативный мониторинг).
- Документация:
  - улучшен onboarding (первый запуск, диагностика, безопасность установки).
  - SEO-пасc по docs-сайту: новые брендовые страницы Stream Hub, page-level title/description, FAQ schema, robots/sitemap и обновлённые CTA.
  - Добавлены отдельные intent-страницы `Stream Hub Web UI`, `Stream Hub API`, `Stream Hub Monitoring`.
  - Внедрены CI-проверки docs SEO (`mkdocs + meta + schema + robots + sitemap`).
  - Усилена индексация: `/admin/` исключён из sitemap, для admin установлен `noindex`.

### Для кого важно

- Операторы с большим числом каналов и частыми Save/Apply.
- Инстансы, где нужны remote API серверы и DASH источники.

## 2026-02-16

### Что изменилось

- Производительность и стабильность конфигурации:
  - async export для снижения задержек на Save,
  - пропуск лишнего import при неизменённом primary config,
  - улучшено логирование медленных apply операций.
- CentOS-совместимость:
  - bundled SQLite (UPSERT support),
  - режимы выбора bundled/system FFmpeg.
- Транскод и устойчивость входов:
  - resilient decode для проблемных сетевых источников,
  - корректная реакция на backpressure.
- Remote Servers:
  - улучшена диагностика ошибок Test/Pull/Import/Streams,
  - поддержан `insecure` для self-signed TLS.

### Для кого важно

- CentOS 7/старые окружения.
- Инстансы с чувствительным к задержкам UI Save.

## 2026-02-15

### Что изменилось

- Добавлены Intel QSV пресеты транскодирования.
- Сделан предсказуемый sharding apply (preflight + явные ошибки).
- Улучшен installer для CentOS (build/verify/fallback сценарии).
- Проведён ребрендинг в пользу `stream` (binary/service naming).

### Для кого важно

- Операторы с Intel Quick Sync.
- Инстансы, где важен “Save без лишних перезапусков”.

## 2026-02-13

- Старт публикации docs-сайта Stream Hub на `stream.centv.ru` (MkDocs Material).
