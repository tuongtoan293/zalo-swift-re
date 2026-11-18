// Đo thời gian chạy của callback timer theo script đã đăng ký nó. Chỉ tiêm khi có biến môi trường
// OLAZ_PROFILE_TIMERS (xem OfficialClientHost). Phải chạy trước mọi host script và trước mã của trang.
//
// Mỗi setTimeout/setInterval/requestAnimationFrame/MutationObserver được gắn nhãn theo khung stack đầu tiên
// ngoài file này: `olaz-<tên>.js:<dòng>` cho host script, `zalo:<file>` cho mã của trang. Mỗi 60 s ghi một dòng
// `[timers]` vào zlog (engine.log): tổng ms, số lần gọi, xếp theo ms giảm dần. Không ghi dữ liệu người dùng.
(() => {
  if (window.__olazTimerProfiler) return;
  window.__olazTimerProfiler = true;
  const now = () => performance.now();
  const stats = new Map();   // nhãn → {ms, n}
  const label = () => {
    const lines = (new Error().stack || '').split('\n');
    for (const l of lines) {
      if (!l || l.includes('olaz-timer-profiler')) continue;
      const host = l.match(/olaz-([\w-]+)\.js:(\d+)/);
      if (host) return 'olaz-' + host[1] + ':' + host[2];
      const page = l.match(/zalo-app:\/\/[^\s)]*?\/([^/\s)?]+?)(?:\?[^\s):]*)?:\d+/);
      if (page) return 'zalo:' + page[1];
    }
    return 'khac';
  };
  const add = (key, ms) => { const s = stats.get(key); if (s) { s.ms += ms; s.n++; } else stats.set(key, { ms, n: 1 }); };
  const wrap = (fn, key) => typeof fn !== 'function' ? fn : function (...a) {
    const t = now();
    try { return fn.apply(this, a); } finally { add(key, now() - t); }
  };

  const st = window.setTimeout, si = window.setInterval, raf = window.requestAnimationFrame;
  window.setTimeout = function (fn, ms, ...a) { return st.call(this, wrap(fn, 'T ' + label()), ms, ...a); };
  // Stack của user script không mang sourceURL nên hay ra 'khac': kèm đầu mã hàm để phân biệt các interval cùng chu kỳ.
  const name = (fn) => { const l = label(); if (l !== 'khac') return l; try { return 'khac{' + String(fn).replace(/\s+/g, ' ').slice(0, 60) + '}'; } catch { return l; } };
  window.setInterval = function (fn, ms, ...a) { return si.call(this, wrap(fn, 'I' + (ms | 0) + ' ' + name(fn)), ms, ...a); };
  if (raf) window.requestAnimationFrame = function (fn) { return raf.call(this, wrap(fn, 'R ' + label())); };
  const MO = window.MutationObserver;
  if (MO) window.MutationObserver = class extends MO { constructor(cb) { super(wrap(cb, 'M ' + label())); } };

  // Slice Redux nào đổi bao nhiêu lần: cho biết lúc rảnh store có đứng yên không (cổng __olazGate dựa vào đó).
  const slices = new Map();
  let watched = null, prev = null;
  si.call(window, () => {
    const store = window.__zaloStore;
    if (!store || store === watched) return;
    watched = store; prev = store.getState();
    store.subscribe(() => {
      const s = store.getState();
      if (s === prev) return;
      for (const k of Object.keys(s)) if (s[k] !== (prev && prev[k])) slices.set(k, (slices.get(k) || 0) + 1);
      prev = s;
    });
  }, 1000);

  const t0 = now();
  si.call(window, () => {
    const span = (now() - t0) / 1000;
    const rows = [...stats.entries()].sort((a, b) => b[1].ms - a[1].ms);
    const total = rows.reduce((s, [, v]) => s + v.ms, 0);
    const top = rows.slice(0, 25).map(([k, v]) => k + ' ' + v.ms.toFixed(0) + 'ms/' + v.n);
    try {
      webkit.messageHandlers.zlog.postMessage('[timers] ' + location.pathname + ' sau ' + span.toFixed(0) + 's tong ' +
        total.toFixed(0) + 'ms rev ' + (window.__olazStoreRev | 0) + ' slices ' +
        [...slices.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([k, n]) => k + ':' + n).join(',') +
        ' | ' + top.join(' | '));
    } catch {}
  }, 60000);
})();
