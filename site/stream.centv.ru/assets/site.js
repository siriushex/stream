/* Stream Hub site JS (tiny).
 * - Copy buttons for code blocks
 */

(function () {
  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'absolute';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
    return Promise.resolve();
  }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('button[data-copy]');
    if (!btn) return;
    var sel = btn.getAttribute('data-copy');
    var el = document.querySelector(sel);
    if (!el) return;
    copyText(el.innerText || el.textContent || '').then(function () {
      var prev = btn.textContent;
      btn.textContent = 'Copied';
      setTimeout(function () { btn.textContent = prev; }, 900);
    });
  });
})();

