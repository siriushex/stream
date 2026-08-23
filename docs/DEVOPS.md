# DEVOPS

## 1. Окружения
- Test: хост `.2` (разрешены быстрые итерации и частые рестарты).
- Production: хост `.6` (только контролируемые обновления по явному запросу).

Принцип: сначала проверка на `.2`, затем перенос на `.6`.

## 2. Build и базовые проверки

### 2.1 Сборка
```bash
./configure.sh && make -j"$(nproc)"
```

### 2.2 Минимальный quality gate
```bash
node --check web/app.js
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

### 2.3 Таргетные тесты по измененному контуру
Примеры:
```bash
./stream scripts/tests/ai_observability_collection_gate_unit.lua
./stream scripts/tests/observability_master_switch_migration_unit.lua
./stream scripts/tests/dvb_autosearch_queue_unit.lua
./stream scripts/tests/dvb_autosearch_type_flip_nodata_pes_unit.lua
./stream scripts/tests/auth_backend_unit.lua
```

Для Stream Hub 1.3 дополнительно:

```bash
contrib/ci/test_softcam_helpers.sh
contrib/ci/test_playout_helpers.sh
contrib/ci/test_http_buffer_helpers.sh
contrib/ci/smoke_native_hls_playout.sh
contrib/ci/smoke_http_buffer_av_failover.sh
```

Newcamd необходимо собирать и проверять на Linux с OpenSSL development headers.
Успешная macOS-сборка без `modules/softcam/cam/newcamd.o` не является
доказательством поддержки Newcamd. Linux gate должен подтвердить наличие этого
object file, успешный SoftCAM helper test и внешний FFmpeg decode video/audio.

## 3. Деплой

### 3.1 Подготовка артефакта
1. Сборка и tests в локальном репо.
2. Проверка `git status` и состава diff.
3. Коммит в `main` только после зелёных проверок.

Release bundle содержит `STREAM_BUILD_INFO.txt`: product version, точный Git
commit, UTC build time, architecture/profile и SHA-256 packaged Stream binary.
По умолчанию provenance writer отказывается создавать метаданные из dirty
working tree; `STREAM_ALLOW_DIRTY_BUILD=1` допустим только для явно помеченного
локального эксперимента, не для release/canary артефакта.

### 3.2 Установка через installer
Поддерживаются скрипты:
- `/Users/mac/0009/astra/install.sh`
- `/Users/mac/0009/astra/deploy/stream.centv.ru/install.sh`
- bootstrap wrappers для CentOS/CentOS7/macOS.

Режимы:
- `--mode source` (сборка на целевом хосте)
- `--mode binary` (готовый бинарник)

Примечание: для старых CentOS предусмотрен fallback bootstrap на HTTP, см. риски в security review.

### 3.3 Systemd units
- Шаблон: `stream@.service`
- Инстансы: `stream@<name>.service`
- Конфиги: `/etc/stream/<name>.json`

Обязательный пост-деплой smoke:
1. `systemctl status stream@<name> --no-pager`
2. `journalctl -u stream@<name> -n 200 --no-pager`
3. Проверка HTTP/UI/API инстанса.
4. Десятиминутная проверка финального output: стабильный bitrate, CC/PES delta
   равны нулю, `cw_applied` растёт на odd/even сменах, FFmpeg декодирует video и
   audio без повторяющихся PPS/MMCO/AC-3 ошибок.

## 4. Rollback
1. Остановить только затронутый unit.
2. Вернуть предыдущий бинарник/конфиг из backup.
3. Запустить unit и повторить smoke.
4. Зафиксировать причину и шаги в `AI_NOTES.md`.

## 5. CI и pre-commit hygiene
- Скрипт контроля утечек: `scripts/ci/check_sensitive_data.sh`.
- Hooks installer: `scripts/dev/install_git_hooks.sh`.
- Доп. проверки docs/seo: `scripts/ci/check_docs_seo.sh` (для `site/*`).

Рекомендуемый pre-push минимум:
```bash
scripts/ci/check_sensitive_data.sh --staged
node --check web/app.js
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

## 6. Операционные правила
1. Не деплоить в `.6` без успешного прогона в `.2`.
2. Не менять одновременно несколько прод-инстансов без окна отката.
3. Любые high-risk toggles включать поэтапно (observability, auto-search, type-flip).
4. Для проблем вещания приоритет: стабилизировать dataplane, затем возвращать observability/features.

## 7. Runbook заметки
- Для работ на `.2`/`.6` использовать локальный skill: `/Users/mac/0009/astra/skills/stream-deploy-2-6/SKILL.md`.
- Все команды с доступами/ключами выполнять вне публичной документации и без сохранения секретов в git.
