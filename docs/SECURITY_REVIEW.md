# SECURITY REVIEW

## 1. Метод
Приоритеты:
- MUST: критичный риск, требует обязательного контроля до production rollout.
- SHOULD: важное улучшение, планируется в ближайшие этапы.
- NICE: полезное усиление без срочного блокера.

Покрытые контуры:
- Web/API auth (`scripts/auth.lua`, `scripts/api.lua`, `scripts/config.lua`)
- Remote servers integration (`scripts/remote_servers.lua`)
- Install/deploy scripts (`install.sh`, `deploy/stream.centv.ru/*`)
- Secret hygiene и CI checks (`scripts/ci/check_sensitive_data.sh`)

## 2. Ключевые наблюдения
- В проекте есть bootstrap-механизм `ensure_admin()` с созданием admin-пользователя при пустой БД.
- API включает явные коды ошибок auth и per-endpoint telemetry (включая 401/403/302).
- Есть защита от утечек в git через регулярный sensitive-data scan.
- Remote mutating actions rate-limited и audit-логируются.

## 3. Findings

### MUST
1. Bootstrap credentials risk
   - Контекст: при пустой базе создается `admin/admin` (с предупреждением в лог).
   - Риск: компрометация при несмененном пароле после первого старта.
   - Требование: принудительная смена пароля на первом входе или блокировка опасных admin-операций до смены.

### SHOULD
1. Installer transport downgrade (HTTPS -> HTTP fallback)
   - Контекст: bootstrap для старых CentOS может падать обратно на HTTP.
   - Риск: MITM при начальной установке.
   - Рекомендация: сохранить fallback только как явно подтверждаемый insecure mode; по умолчанию strict HTTPS + checksum pinning.

2. Remote credentials lifecycle
   - Контекст: Servers integration использует логин/пароль и токены для удаленных API.
   - Риск: операционный (ротация, контроль срока жизни, политика хранения).
   - Рекомендация: формализовать ротацию, TTL и masking policy в docs/ops, минимизировать время жизни сессий.

3. SSRF perimeter review for remote fetch paths
   - Контекст: есть защитные комментарии и контур обхода SSRF-ограничений через loopback для некоторых операций.
   - Риск: расширение входных источников может открыть нежелательные egress paths.
   - Рекомендация: централизованный allowlist policy для remote URLs и тесты на deny/private ranges.

### NICE
1. Security regression suite consolidation
   - Объединить auth/remote/security unit-тесты в отдельный CI job с обязательным статусом.

2. Audit enrichment
   - Добавить стандартные поля correlation/request-id в security-critical audit events для ускорения расследований.

## 4. Уже реализованные контрмеры
- `check_sensitive_data.sh` блокирует ключи/токены/PII/служебные логи и внутренние адреса в git.
- Token/secret masking присутствует в UI и API слоях для части полей.
- Для `dvr_v1` remote bridge (`/api/v1/servers/streams/get|list`) `dvr.source_url` отдается в redacted-виде без `user:pass@`.
- API ошибок и auth-статусов возвращает корректные коды и сообщения.
- Remote actions проходят rate-limit и audit.
- Observability имеет master-switch и режим read-only OFF для минимизации влияния на runtime.

## 5. Рекомендуемый план закрытия
1. Закрыть MUST:
   - внедрить forced password change on first login.
2. Закрыть SHOULD:
   - hardened installer transport policy;
   - credential lifecycle policy;
   - SSRF perimeter tests.
3. NICE:
   - отдельный security CI lane и расширение audit metadata.
