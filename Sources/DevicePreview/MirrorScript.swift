// 모든 기기 웹뷰에 문서 시작 시점에 주입되는 스크립트.
//
// - 사용자가 직접 한 조작(isTrusted 이벤트)만 네이티브로 보낸다.
//   다른 기기에서 재생된 합성 이벤트는 isTrusted=false 라 다시 퍼지지 않는다.
// - 네이티브는 "마지막으로 사용자가 만진 기기"(active)의 메시지만 나머지 기기로 보낸다.
// - 받은 기기는 같은 요소를 CSS 경로로 찾고, 레이아웃이 달라 못 찾으면
//   텍스트/name/placeholder/aria-label 등으로 가장 비슷한 요소를 찾는다.
enum MirrorScript {
    static let source = #"""
(() => {
  if (window.__mirror) return;
  const post = (m) => { try { window.webkit.messageHandlers.mirror.postMessage(m); } catch (e) {} };
  const esc = (s) => (window.CSS && CSS.escape) ? CSS.escape(s) : s;
  const ACTIONABLE = 'a,button,input,select,textarea,label,summary,[role=button],[role=tab],[role=link],[role=option],[role=menuitem],[role=checkbox],[role=switch],[role=radio],[tabindex]';
  const textOf = (el) => (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 80);
  const visible = (el) => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
  const isForm = (el) => el.matches && el.matches('input,select,textarea');

  function selectorOf(el) {
    const parts = [];
    let node = el;
    while (node && node.nodeType === 1 && node !== document.documentElement) {
      if (node.id) { parts.unshift('#' + esc(node.id)); break; }
      let part = node.tagName.toLowerCase();
      const parent = node.parentElement;
      if (parent) {
        const same = Array.prototype.filter.call(parent.children, (c) => c.tagName === node.tagName);
        if (same.length > 1) part += ':nth-of-type(' + (same.indexOf(node) + 1) + ')';
      }
      parts.unshift(part);
      node = parent;
    }
    return parts.join(' > ');
  }

  function describe(el, withText = true) {
    return {
      sel: selectorOf(el),
      tag: el.tagName.toLowerCase(),
      text: withText && !isForm(el) ? textOf(el) : null,
      name: el.getAttribute('name'),
      type: el.getAttribute('type'),
      placeholder: el.getAttribute('placeholder'),
      aria: el.getAttribute('aria-label'),
      href: el.getAttribute('href'),
      cls: typeof el.className === 'string' ? el.className : null,
    };
  }

  function resolve(d) {
    let el = null;
    try { el = d.sel ? document.querySelector(d.sel) : null; } catch (e) {}
    if (el && el.tagName.toLowerCase() === d.tag && visible(el) && (!d.text || textOf(el) === d.text)) return el;

    // 레이아웃이 달라 경로로 못 찾으면 속성/텍스트로 가장 비슷한 요소를 찾는다
    let best = null, bestScore = 0;
    for (const c of document.getElementsByTagName(d.tag)) {
      if (!visible(c)) continue;
      let s = 0;
      if (d.text && textOf(c) === d.text) s += 3;
      if (d.name && c.getAttribute('name') === d.name) s += 3;
      if (d.placeholder && c.getAttribute('placeholder') === d.placeholder) s += 3;
      if (d.aria && c.getAttribute('aria-label') === d.aria) s += 2;
      if (d.href && c.getAttribute('href') === d.href) s += 2;
      if (d.cls && c.className === d.cls) s += 1;
      if (d.type && c.getAttribute('type') === d.type) s += 1;
      if (s > bestScore) { best = c; bestScore = s; }
    }
    if (best && bestScore >= 3) return best;
    if (el && el.tagName.toLowerCase() === d.tag && visible(el) && !d.text) return el;
    return null;
  }

  // ---------- 보내기 ----------
  let lastActive = 0;
  const markActive = (e) => {
    if (!e.isTrusted) return;
    const now = Date.now();
    if (now - lastActive > 250) { lastActive = now; post({ type: 'active' }); }
  };
  ['pointerdown', 'keydown', 'wheel', 'touchstart'].forEach((t) =>
    addEventListener(t, markActive, { capture: true, passive: true }));

  addEventListener('click', (e) => {
    if (!e.isTrusted || !(e.target instanceof Element)) return;
    const el = e.target.closest(ACTIONABLE) || e.target;
    post({ type: 'click', target: describe(el) });
  }, true);

  addEventListener('input', (e) => {
    const el = e.target;
    if (!e.isTrusted || !isForm(el) || el.type === 'checkbox' || el.type === 'radio' || el.type === 'file') return;
    post({ type: 'input', target: describe(el), value: el.value });
  }, true);

  addEventListener('change', (e) => {
    const el = e.target;
    if (!e.isTrusted || !isForm(el) || !(el.type === 'checkbox' || el.type === 'radio')) return;
    post({ type: 'check', target: describe(el), checked: el.checked });
  }, true);

  const KEYS = new Set(['Enter', 'Escape', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight']);
  addEventListener('keydown', (e) => {
    if (!e.isTrusted || !KEYS.has(e.key)) return;
    const el = document.activeElement && document.activeElement !== document.body ? document.activeElement : null;
    post({ type: 'key', key: e.key, code: e.code, target: el ? describe(el, false) : null });
  }, true);

  const ratio = (a, b) => (b > 0 ? a / b : 0);
  let pendingScroll = null;
  addEventListener('scroll', (e) => {
    const t = e.target === document ? document.scrollingElement : e.target;
    if (!(t instanceof Element)) return;
    const queued = pendingScroll !== null;
    pendingScroll = t;
    if (queued) return;
    requestAnimationFrame(() => {
      const el = pendingScroll; pendingScroll = null;
      const root = el === document.scrollingElement;
      post({
        type: 'scroll',
        target: root ? null : describe(el, false),
        y: ratio(el.scrollTop, el.scrollHeight - el.clientHeight),
        x: ratio(el.scrollLeft, el.scrollWidth - el.clientWidth),
      });
    });
  }, { capture: true, passive: true });

  const notifyNav = () => post({ type: 'nav', href: location.href });
  for (const m of ['pushState', 'replaceState']) {
    const orig = history[m];
    history[m] = function (...args) { const r = orig.apply(this, args); notifyNav(); return r; };
  }
  addEventListener('popstate', notifyNav);

  const reportViewport = () => post({ type: 'viewport', w: innerWidth, h: innerHeight });
  addEventListener('resize', reportViewport);
  addEventListener('DOMContentLoaded', reportViewport);
  addEventListener('load', reportViewport);

  // ---------- 재생 ----------
  const submittedAt = new WeakMap();
  addEventListener('submit', (e) => submittedAt.set(e.target, Date.now()), true);

  function flash(el, color) {
    const r = el.getBoundingClientRect();
    const d = document.createElement('div');
    Object.assign(d.style, {
      position: 'fixed', left: r.left + 'px', top: r.top + 'px', width: r.width + 'px', height: r.height + 'px',
      outline: '2px solid ' + color, outlineOffset: '1px', borderRadius: '4px', pointerEvents: 'none',
      zIndex: '2147483647', transition: 'opacity .4s',
    });
    document.documentElement.appendChild(d);
    setTimeout(() => { d.style.opacity = '0'; }, 300);
    setTimeout(() => d.remove(), 800);
  }

  function setNativeValue(el, value) {
    const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype
      : el instanceof HTMLSelectElement ? HTMLSelectElement.prototype
      : HTMLInputElement.prototype;
    const desc = Object.getOwnPropertyDescriptor(proto, 'value');
    if (desc && desc.set) desc.set.call(el, value); else el.value = value;
  }

  function pointerSequence(el) {
    const r = el.getBoundingClientRect();
    const base = { bubbles: true, cancelable: true, composed: true, view: window, button: 0,
      clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 };
    const p = { ...base, pointerId: 1, isPrimary: true, pointerType: 'mouse' };
    el.dispatchEvent(new PointerEvent('pointerdown', p));
    el.dispatchEvent(new MouseEvent('mousedown', base));
    if (typeof el.focus === 'function') el.focus({ preventScroll: true });
    el.dispatchEvent(new PointerEvent('pointerup', p));
    el.dispatchEvent(new MouseEvent('mouseup', base));
    el.click();
  }

  const miss = (m) => post({ type: 'miss', what: m.type });

  function apply(m) {
    switch (m.type) {
      case 'click': {
        const el = resolve(m.target);
        if (!el) return miss(m);
        // Enter 로 이미 제출된 폼의 submit 버튼 클릭이 따라오면 중복 제출을 막는다
        if (el.form && el.type === 'submit' && Date.now() - (submittedAt.get(el.form) || 0) < 600) return;
        flash(el, '#ff3b6b');
        pointerSequence(el);
        break;
      }
      case 'input': {
        const el = resolve(m.target);
        if (!el) return miss(m);
        if (el.value !== m.value) setNativeValue(el, m.value);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        if (el instanceof HTMLSelectElement) el.dispatchEvent(new Event('change', { bubbles: true }));
        break;
      }
      case 'check': {
        const el = resolve(m.target);
        if (!el) return miss(m);
        if (el.checked !== m.checked) el.click();
        break;
      }
      case 'key': {
        const el = (m.target && resolve(m.target)) || document.activeElement || document.body;
        const opts = { key: m.key, code: m.code, bubbles: true, cancelable: true };
        const ok = el.dispatchEvent(new KeyboardEvent('keydown', opts));
        el.dispatchEvent(new KeyboardEvent('keyup', opts));
        // 합성 Enter 는 폼을 제출하지 않는다. submit 버튼이 있는 폼은 원본에서
        // 버튼 클릭이 따라오므로, 버튼 없는 폼만 직접 제출한다.
        if (ok && m.key === 'Enter' && el.form && el.matches('input') &&
            !el.form.querySelector('button:not([type]),button[type=submit],input[type=submit]')) {
          el.form.requestSubmit();
        }
        break;
      }
      case 'scroll': {
        const el = m.target ? resolve(m.target) : document.scrollingElement;
        if (!el) return;
        el.scrollTop = m.y * (el.scrollHeight - el.clientHeight);
        el.scrollLeft = m.x * (el.scrollWidth - el.clientWidth);
        break;
      }
      case 'nav': {
        // 클릭 재생으로 이미 같은 곳에 가 있는 경우가 대부분이라 잠깐 기다렸다가 확인한다
        setTimeout(() => {
          if (location.href === m.href) return;
          const u = new URL(m.href);
          if (u.origin === location.origin) {
            history.pushState(history.state, '', m.href);
            dispatchEvent(new PopStateEvent('popstate', { state: history.state }));
          } else {
            location.href = m.href;
          }
        }, 400);
        break;
      }
    }
  }

  window.__mirror = { apply: (m) => { try { apply(m); } catch (e) { console.warn('[mirror]', e); } } };
})();
"""#

    /// 폰/태블릿은 터치 기기처럼 보이게 한다 (navigator.maxTouchPoints 로 기기를 구분하는 코드용)
    static let touchSpoof = #"""
try { Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: () => 5, configurable: true }); } catch (e) {}
"""#
}
