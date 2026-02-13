---
title: Admin
hide:
  - navigation
  - toc
---

# Редактор сайта

<div class="sh-admin" id="sh-admin-root" markdown="0">
  <div class="sh-admin__bar">
    <div class="sh-admin__title">
      <strong>Редактор</strong>
      <span class="sh-admin__muted">Редактирование текстов и картинок для сайта Stream Hub.</span>
    </div>
    <div class="sh-admin__actions">
      <button class="md-button md-button--primary" id="sh-admin-save" type="button" disabled>Сохранить</button>
      <button class="md-button" id="sh-admin-build" type="button">Собрать и опубликовать</button>
    </div>
  </div>

  <div class="sh-admin__layout">
    <aside class="sh-admin__files" aria-label="Файлы">
      <div class="sh-admin__files-head">
        <div class="sh-admin__files-title">Страницы</div>
        <button class="md-button md-button--small" id="sh-admin-refresh" type="button">Обновить</button>
      </div>
      <div class="sh-admin__files-list" id="sh-admin-files"></div>
    </aside>

    <main class="sh-admin__editor" aria-label="Редактор">
      <div class="sh-admin__editor-head">
        <div class="sh-admin__path" id="sh-admin-path">Выберите страницу слева</div>
        <div class="sh-admin__tools">
          <button class="md-button md-button--small" id="sh-admin-insert-link" type="button">Ссылка</button>
          <button class="md-button md-button--small" id="sh-admin-insert-img" type="button">Картинка</button>
          <button class="md-button md-button--small" id="sh-admin-insert-note" type="button">Заметка</button>
          <label class="md-button md-button--small sh-admin__upload">
            Загрузить…
            <input id="sh-admin-upload" type="file" accept=".png,.jpg,.jpeg,.webp,.svg" hidden>
          </label>
        </div>
      </div>

      <textarea class="sh-admin__textarea" id="sh-admin-text" spellcheck="false" placeholder="Текст страницы (Markdown)"></textarea>
      <div class="sh-admin__status" id="sh-admin-status"></div>
    </main>
  </div>

  <noscript>
    <div class="admonition warning">
      <p class="admonition-title">Нужен JavaScript</p>
      <p>Редактор работает только с включённым JavaScript.</p>
    </div>
  </noscript>
</div>

