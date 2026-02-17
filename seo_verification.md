# SEO Verification

## Техническая проверка

| Проверка | Статус | Комментарий |
|---|---|---|
| `mkdocs build --strict` | PASS | Сборка проходит без ошибок. |
| Page-level title/description | PASS | Для 16 ключевых страниц заданы SEO title и description через `overrides/main.html`. |
| Title длина 50–60 | PASS | Для ключевых страниц в диапазоне ~50–57 символов. |
| Description длина 140–160 | PASS | Для ключевых страниц в диапазоне ~141–159 символов. |
| Canonical URL | PASS | Присутствует на ключевых страницах. |
| Open Graph / Twitter | PASS | OG title/description/url и Twitter card присутствуют. |
| Sitemap | PASS | `site/sitemap.xml` генерируется. |
| robots.txt | PASS | `site/robots.txt` присутствует и содержит `Sitemap`. |
| FAQ Schema | PASS | На `/faq/` присутствует `FAQPage` с 5 вопросами. |
| Внутренние ссылки | PASS | `missing_count=0` (при исключении download endpoints `/stream`, `install*.sh`, `stream-src.tar.gz`). |
| Дубли `manual/*.html` | PASS | Legacy HTML исключены из публикации. |
| Поиск MkDocs | PASS | `site/search/search_index.json` присутствует. |

## Чек-лист PASS / REVIEW

- `title/description` у 10+ ключевых страниц обновлены: **PASS**
- `title/description` у 16 ключевых страниц обновлены: **PASS**
- `canonical/sitemap/robots` корректны: **PASS**
- есть отдельная SEO-страница про Stream Hub: **PASS**
- FAQ содержит search-ориентированные блоки: **PASS**
- бренд “Stream Hub” доминирует в заголовках и мета-тегах: **PASS**
- терминология унифицирована: **PASS**
- внутренние ссылки закрывают сценарий пользователя: **PASS**

## Ручной smoke (визуальный)

- Desktop (light/dark): **REVIEW**
- Mobile (hero/cards/FAQ details): **REVIEW**

Комментарий: технические SEO-проверки закрыты, но финальный визуальный проход на проде перед релизом обязателен.
