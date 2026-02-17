# SEO Next Steps (30 Days)

## Готовность к запуску

Текущая готовность: **High (технически готово к выкладке)**.

Что уже готово:

- SEO-структура страниц и брендовые лэндинги.
- Page-level title/description, OG/Twitter, canonical.
- robots + sitemap + FAQ Schema.
- Базовый UX/контентный путь “установка -> запуск -> проверка -> диагностика”.

## План на 30 дней

## Неделя 1: Индексация и базовая аналитика

1. Подключить и проверить Google Search Console для `https://stream.centv.ru`.
2. Отправить `sitemap.xml`, проверить coverage и canonical selection.
3. Завести baseline-метрики:
   - impressions,
   - CTR,
   - средняя позиция,
   - branded vs non-branded queries.

## Неделя 2: CTR и сниппеты

1. Проверить первые SERP-сниппеты ключевых страниц (бренд + IPTV intent).
2. Точечно скорректировать title/description страниц с CTR ниже baseline.
3. Сформировать отдельный mini-cluster для monitoring intent:
   - усилить перелинковку между `about/stream-hub-monitoring`, `manual/observability` и `manual/logs`,
   - добавить 2 коротких how-to блока с диагностическими сценариями.

## Неделя 3: Контентный рост и внутренние связи

1. Расширить FAQ на основе реальных запросов из GSC.
2. Добавить контекстные внутренние ссылки из manual на `/about/*`.
3. Добавить короткие “How-to” блоки в high-impression страницах.

## Неделя 4: Авторитет и внешние сигналы

1. Подготовить 3–5 нейтральных external mentions:
   - профильные сообщества,
   - dev/ops каталоги,
   - тематические статьи.
2. Проверить consistency бренда Stream Hub во внешних упоминаниях.
3. Пересчитать CTR/позиции и определить следующие priority pages.

## Рекомендованный следующий прорыв

**GSC-driven SEO iteration**: каждые 7 дней обновлять title/description/FAQ только на страницах с высоким impression и низким CTR.  
Это даёт самый быстрый прирост органики без риска переспама и без изменения продуктовой сути.

## Backlog (после 30 дней)

- Добавить release tags в GitHub и связать changelog с tagged releases.
- Добавить checksum/signature блок для installer/binary (доверие + SEO поведенка).
- Внедрить автоматическую визуальную регрессию docs (mobile/desktop, light/dark).
