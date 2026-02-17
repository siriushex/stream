// Stream Hub docs JS.
// Минимальные эффекты (только landing), без тяжёлых библиотек.

(function () {
  const prefersReducedMotion = () =>
    window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function initCopyFeedback() {
    if (window.__shCopyFeedbackBound) return;
    window.__shCopyFeedbackBound = true;

    const copiedLabel = "Скопировано";
    const resetDelayMs = 1300;

    document.addEventListener("click", (ev) => {
      const btn = ev.target && ev.target.closest ? ev.target.closest(".md-clipboard") : null;
      if (!btn) return;

      const prevLabel = btn.getAttribute("aria-label") || "";
      btn.classList.add("sh-copied");
      btn.setAttribute("aria-label", copiedLabel);
      btn.setAttribute("data-md-state", copiedLabel);

      window.setTimeout(() => {
        btn.classList.remove("sh-copied");
        if (prevLabel) {
          btn.setAttribute("aria-label", prevLabel);
        } else {
          btn.removeAttribute("aria-label");
        }
        btn.removeAttribute("data-md-state");
      }, resetDelayMs);
    });
  }

  function initOnboardingProgress() {
    const root = document.querySelector(".sh-onboarding-progress");
    if (!root) return;

    const cards = [...document.querySelectorAll(".sh-grid .sh-card")];
    if (!cards.length) return;

    if (prefersReducedMotion() || !("IntersectionObserver" in window)) return;

    const items = [...root.querySelectorAll(".sh-progress-item")];
    if (!items.length) return;

    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const idx = cards.indexOf(entry.target);
          if (idx < 0 || idx >= items.length) continue;
          items[idx].classList.add("is-active");
        }
      },
      { threshold: 0.35 }
    );

    for (const card of cards) io.observe(card);
  }

  function initLandingFx() {
    const landing = document.querySelector(".sh-landing");
    // Маркер для CSS: главная страница = “витрина”.
    document.body.classList.toggle("sh-home", !!landing);

    if (!landing) return;

    // Лёгкий reveal без тяжёлых pointer-эффектов.
    const revealEls = [
      ...document.querySelectorAll(".sh-hero-copy > *"),
      ...document.querySelectorAll(".sh-card"),
      ...document.querySelectorAll(".sh-section h2, .sh-section h3"),
    ];
    for (const el of revealEls) el.classList.add("sh-reveal");

    if (prefersReducedMotion() || !("IntersectionObserver" in window)) {
      for (const el of revealEls) el.classList.add("is-in");
      return;
    }

    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (!e.isIntersecting) continue;
          e.target.classList.add("is-in");
          io.unobserve(e.target);
        }
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    for (const el of revealEls) io.observe(el);
  }

  // MkDocs Material может жить с instant navigation. Поддерживаем оба режима.
  if (window.document$ && typeof window.document$.subscribe === "function") {
    window.document$.subscribe(() => {
      initLandingFx();
      initCopyFeedback();
      initOnboardingProgress();
    });
  } else {
    window.addEventListener("DOMContentLoaded", () => {
      initLandingFx();
      initCopyFeedback();
      initOnboardingProgress();
    });
  }
})();
