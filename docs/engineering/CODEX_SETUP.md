# Codex Environment Setup (Multi‑Agent)

Это требования для корректной параллельной работы нескольких Codex‑агентов с минимальными конфликтами.

## 1. Рабочие директории
- У каждого агента должна быть своя рабочая копия (worktree или отдельный клон).
- Рекомендация: использовать `git worktree`:
  - `git worktree add ../astra-<agent> -b codex/<agent>/<topic>`

## 2. Идентичность Git
- Для каждого агента задаётся уникальный `user.name`/`user.email`:
  - `git config user.name "<agent>"`
  - `git config user.email "<agent>@users.noreply.github.com"`
- Рекомендуется включить rebase при pull:
  - `git config pull.rebase true`

## 3. Правила веток
- Все ветки: `codex/<agent>/<topic>`.
- Запрещены прямые коммиты в `main`.

## 4. CODEOWNERS и review
- Ownership назначен в `.github/CODEOWNERS`.
- Любые изменения в owned‑зонах требуют review от владельцев.

## 5. Доступ к серверу
- SSH‑ключ: `~/.ssh/root_blast`.
- Порт: `40242`.
- Рекомендация: создать алиас в `~/.ssh/config`:
  - `Host astra-prod`
  - `  HostName 178.212.236.2`
  - `  User root`
  - `  Port 40242`
  - `  IdentityFile ~/.ssh/root_blast`

## 6. Codex home
- Убедиться, что `CODEX_HOME` указывает на директорию с навыками/автоматизациями (по умолчанию `~/.codex`).
- Не хранить секреты в репозитории.

## 7. Мини‑чеклист агента
- Перед стартом: `git fetch origin && git pull --rebase`.
- Перед merge: CI зелёный, `CHANGELOG.md` обновлён, есть approvals по CODEOWNERS.
