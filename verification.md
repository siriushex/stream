# verification

## Прогон проверок

| Проверка | Команда/метод | Статус | Комментарий |
|---|---|---|---|
| Сборка документации | `.venv/bin/mkdocs build --strict` | PASS | Сборка успешна. |
| Внутренние ссылки/якоря | кастомный HTML-проход по `site/` | PASS | `missing_count 0`. |
| Синтаксис JS | `node --check docs/javascripts/extra.js` | PASS | Ошибок синтаксиса нет. |
| Доступность ключевых live-страниц | HTTP GET к `/, /quick-start/installation/, /faq/, /manual/troubleshooting/` | PASS | Везде HTTP 200. |
| Onboarding-путь за 1 экран | ревью `docs/index.md` | PASS | Добавлены 3 шага + 2 CTA. |
| FAQ быстрый путь | ревью `docs/faq.md` | PASS | Добавлен быстрый чек-лист + collapsible Q/A. |
| Диагностика “Если не играет” | ревью `docs/manual/troubleshooting.md` | PASS | Есть 8-шаговый checklist и expected output. |
| Безопасность install-коммуникации | ревью `installation.md` + `security.md` | PASS | HTTPS-first + аварийный HTTP fallback с предупреждением. |
| Mobile/desktop visual smoke | ручной UI в браузере | NEED-REVIEW | Требуется финальный визуальный проход на целевом окружении. |
| Светлая/тёмная тема контраст | ручной UI в браузере | NEED-REVIEW | Технически CSS совместим с Material tokens, но нужен финальный manual-check. |

## Что проверить вручную после деплоя

1. Главная (`/`) в light/dark: читаемость hero, pipeline, статусов.
2. `quick-start/installation/`: корректность блоков warning/note на мобильном.
3. `faq/`: скорость открытия/закрытия и визуальная стабильность details.
4. `manual/troubleshooting/`: удобство чтения чек-листа на мобильном.
5. Copy-кнопки в code-block: виден ли статус `Скопировано`.
