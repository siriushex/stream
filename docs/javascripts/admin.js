(() => {
  const isAdminPage = () => {
    const p = window.location.pathname || "";
    return p === "/admin/" || p === "/admin/index.html" || p.startsWith("/admin/");
  };

  if (!isAdminPage()) return;

  const $ = (id) => document.getElementById(id);

  const elRoot = $("sh-admin-root");
  if (!elRoot) return;

  const elFiles = $("sh-admin-files");
  const elPath = $("sh-admin-path");
  const elText = $("sh-admin-text");
  const elStatus = $("sh-admin-status");
  const btnSave = $("sh-admin-save");
  const btnBuild = $("sh-admin-build");
  const btnRefresh = $("sh-admin-refresh");
  const btnLink = $("sh-admin-insert-link");
  const btnImg = $("sh-admin-insert-img");
  const btnNote = $("sh-admin-insert-note");
  const inUpload = $("sh-admin-upload");

  const API = "/admin/api";
  const ADMIN_HEADER = { "X-Stream-Admin": "1" };

  const state = {
    files: [],
    active: null,
    activeContent: "",
    dirty: false,
    saving: false,
    building: false,
    loading: false,
  };

  const setStatus = (msg, kind) => {
    elStatus.classList.remove("is-error", "is-ok");
    if (kind === "error") elStatus.classList.add("is-error");
    if (kind === "ok") elStatus.classList.add("is-ok");
    elStatus.textContent = msg || "";
  };

  const setButtons = () => {
    btnSave.disabled = !state.active || !state.dirty || state.saving || state.loading;
    btnBuild.disabled = state.building || state.loading;
  };

  const request = async (path, opts = {}) => {
    const res = await fetch(API + path, {
      credentials: "same-origin",
      cache: "no-store",
      ...opts,
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new Error(`${res.status} ${res.statusText}${text ? `: ${text}` : ""}`);
    }
    const ct = res.headers.get("content-type") || "";
    if (ct.includes("application/json")) return res.json();
    return res.text();
  };

  const renderFiles = () => {
    elFiles.innerHTML = "";
    for (const p of state.files) {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "sh-admin__file" + (p === state.active ? " is-active" : "");
      b.textContent = p;
      b.addEventListener("click", () => openFile(p));
      elFiles.appendChild(b);
    }
  };

  const loadFiles = async () => {
    state.loading = true;
    setButtons();
    setStatus("Загружаю список…");
    try {
      const data = await request("/list");
      state.files = Array.isArray(data.files) ? data.files : [];
      renderFiles();
      setStatus(`Файлов: ${state.files.length}`, "ok");
    } catch (e) {
      setStatus(`Ошибка: ${e.message}`, "error");
    } finally {
      state.loading = false;
      setButtons();
    }
  };

  const openFile = async (path) => {
    if (!path) return;
    if (state.dirty) {
      const ok = window.confirm("Есть несохранённые изменения. Открыть другую страницу и потерять их?");
      if (!ok) return;
    }

    state.loading = true;
    state.active = path;
    state.dirty = false;
    setButtons();
    setStatus("Загружаю…");
    elPath.textContent = path;
    renderFiles();

    try {
      const data = await request(`/file?path=${encodeURIComponent(path)}`);
      state.activeContent = String(data.content || "");
      elText.value = state.activeContent;
      setStatus("Готово", "ok");
    } catch (e) {
      setStatus(`Ошибка: ${e.message}`, "error");
    } finally {
      state.loading = false;
      setButtons();
    }
  };

  const saveActive = async () => {
    if (!state.active || state.saving) return;
    state.saving = true;
    setButtons();
    setStatus("Сохраняю…");
    try {
      const content = elText.value || "";
      await request(`/file?path=${encodeURIComponent(state.active)}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          ...ADMIN_HEADER,
        },
        body: JSON.stringify({ content }),
      });
      state.activeContent = content;
      state.dirty = false;
      setStatus("Сохранено", "ok");
      renderFiles();
    } catch (e) {
      setStatus(`Ошибка: ${e.message}`, "error");
    } finally {
      state.saving = false;
      setButtons();
    }
  };

  const buildAndDeploy = async () => {
    if (state.building) return;
    const ok = window.confirm("Собрать и опубликовать сайт сейчас?");
    if (!ok) return;

    state.building = true;
    setButtons();
    setStatus("Сборка и публикация…");
    try {
      const out = await request("/build", {
        method: "POST",
        headers: {
          ...ADMIN_HEADER,
        },
      });
      const msg = (out && out.message) ? out.message : "Готово";
      setStatus(msg, "ok");
    } catch (e) {
      setStatus(`Ошибка: ${e.message}`, "error");
    } finally {
      state.building = false;
      setButtons();
    }
  };

  const insertAtCursor = (text) => {
    const el = elText;
    const start = el.selectionStart || 0;
    const end = el.selectionEnd || 0;
    const before = el.value.slice(0, start);
    const after = el.value.slice(end);
    el.value = before + text + after;
    const pos = start + text.length;
    el.setSelectionRange(pos, pos);
    el.focus();
    state.dirty = true;
    setButtons();
    setStatus("Есть несохранённые изменения");
  };

  const handleTab = (e) => {
    if (e.key !== "Tab") return;
    e.preventDefault();

    const el = elText;
    const value = el.value;
    const start = el.selectionStart || 0;
    const end = el.selectionEnd || 0;

    // One line: insert a tab char.
    if (start === end) {
      insertAtCursor("\t");
      return;
    }

    const lineStart = value.lastIndexOf("\n", start - 1) + 1;
    const lineEnd = value.indexOf("\n", end);
    const blockEnd = (lineEnd === -1) ? value.length : lineEnd;
    const block = value.slice(lineStart, blockEnd);
    const lines = block.split("\n");

    if (e.shiftKey) {
      // Unindent.
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].startsWith("\t")) lines[i] = lines[i].slice(1);
        else if (lines[i].startsWith("    ")) lines[i] = lines[i].slice(4);
        else if (lines[i].startsWith("  ")) lines[i] = lines[i].slice(2);
      }
    } else {
      // Indent.
      for (let i = 0; i < lines.length; i++) lines[i] = "\t" + lines[i];
    }

    const replaced = lines.join("\n");
    el.value = value.slice(0, lineStart) + replaced + value.slice(blockEnd);
    el.setSelectionRange(lineStart, lineStart + replaced.length);
    el.focus();
    state.dirty = true;
    setButtons();
    setStatus("Есть несохранённые изменения");
  };

  const uploadFile = async (file) => {
    if (!file) return;
    const fd = new FormData();
    fd.append("file", file);

    setStatus("Загрузка файла…");
    try {
      const res = await fetch(API + "/upload", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          ...ADMIN_HEADER,
        },
        body: fd,
      });
      if (!res.ok) {
        const t = await res.text().catch(() => "");
        throw new Error(`${res.status} ${res.statusText}${t ? `: ${t}` : ""}`);
      }
      const data = await res.json();
      if (data && data.url) {
        insertAtCursor(`![картинка](${data.url})`);
        setStatus("Файл загружен", "ok");
      } else {
        setStatus("Файл загружен", "ok");
      }
    } catch (e) {
      setStatus(`Ошибка: ${e.message}`, "error");
    }
  };

  elText.addEventListener("keydown", (e) => {
    handleTab(e);
    const isSave = (e.key === "s" || e.key === "S") && (e.ctrlKey || e.metaKey);
    if (isSave) {
      e.preventDefault();
      saveActive();
    }
  });

  elText.addEventListener("input", () => {
    if (!state.active) return;
    const v = elText.value || "";
    const dirty = v !== state.activeContent;
    if (dirty !== state.dirty) {
      state.dirty = dirty;
      setButtons();
    }
    if (state.dirty) setStatus("Есть несохранённые изменения");
  });

  btnSave.addEventListener("click", saveActive);
  btnBuild.addEventListener("click", buildAndDeploy);
  btnRefresh.addEventListener("click", loadFiles);

  btnLink.addEventListener("click", () => insertAtCursor(`[текст](https://example.com)`));
  btnImg.addEventListener("click", () => insertAtCursor(`![описание](/assets/uploads/filename.png)`));
  btnNote.addEventListener("click", () =>
    insertAtCursor(`\n!!! tip \"Заметка\"\n\tКороткий полезный совет.\n`)
  );

  inUpload.addEventListener("change", () => {
    const f = inUpload.files && inUpload.files[0];
    inUpload.value = "";
    uploadFile(f);
  });

  // Initial load.
  setStatus("Готово");
  setButtons();
  loadFiles();
})();

