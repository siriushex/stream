# Auth Backends: Tech Pack

Этот пакет фиксирует, как в Stream сейчас работает авторизация отдачи потоков через внешние порталы (Ministra / TMS / generic), и что требуется для полноценной продуктовой реализации.

Состав:

- `contract.md` — формальный контракт (request/response, поведение, коды, заголовки, cache/recheck).
- `test-matrix.md` — тест-кейсы (unit/integration/e2e) для QA и регрессии.
- `acceptance-checklist.md` — чеклист приёмки и операционные критерии готовности.

Базовые ссылки на код:

- `/Users/mac/0009/astra/scripts/auth.lua`
- `/Users/mac/0009/astra/scripts/server.lua`
- `/Users/mac/0009/astra/web/app.js`
- `/Users/mac/0009/astra/web/index.html`
