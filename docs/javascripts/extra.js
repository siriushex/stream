// Stream Hub docs JS.
// Минимальные эффекты (только landing), без тяжёлых библиотек.

(function () {
  const prefersReducedMotion = () =>
    window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function initLandingFx() {
    const landing = document.querySelector(".sh-landing");
    if (!landing) return;

    // Reveal-on-scroll
    const revealEls = [
      ...document.querySelectorAll(".sh-hero-copy > *"),
      ...document.querySelectorAll(".sh-card"),
      ...document.querySelectorAll(".sh-section h2, .sh-section h3"),
    ];
    for (const el of revealEls) el.classList.add("sh-reveal");

    if (!prefersReducedMotion() && "IntersectionObserver" in window) {
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
    } else {
      for (const el of revealEls) el.classList.add("is-in");
    }

    // Pointer parallax (hero only)
    const hero = document.querySelector(".sh-hero");
    if (!hero) return;
    if (prefersReducedMotion()) return;

    let raf = 0;
    let lastX = 0;
    let lastY = 0;

    const apply = () => {
      raf = 0;
      hero.style.setProperty("--sh-mx", `${lastX}px`);
      hero.style.setProperty("--sh-my", `${lastY}px`);
    };

    const onMove = (ev) => {
      const r = hero.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const cy = r.top + r.height / 2;
      const dx = (ev.clientX - cx) / Math.max(1, r.width / 2);
      const dy = (ev.clientY - cy) / Math.max(1, r.height / 2);
      // clamp
      const cdx = Math.max(-1, Math.min(1, dx));
      const cdy = Math.max(-1, Math.min(1, dy));
      lastX = Math.round(cdx * 24);
      lastY = Math.round(cdy * 18);
      if (!raf) raf = requestAnimationFrame(apply);
    };

    const onLeave = () => {
      lastX = 0;
      lastY = 0;
      if (!raf) raf = requestAnimationFrame(apply);
    };

    hero.addEventListener("pointermove", onMove, { passive: true });
    hero.addEventListener("pointerleave", onLeave, { passive: true });
  }

  // MkDocs Material может жить с instant navigation. Поддерживаем оба режима.
  if (window.document$ && typeof window.document$.subscribe === "function") {
    window.document$.subscribe(() => initLandingFx());
  } else {
    window.addEventListener("DOMContentLoaded", () => initLandingFx());
  }
})();
