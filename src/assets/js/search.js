/*
 * Home page instant search.
 *
 * Reads the build-time index (search-index.js -> window.__TS_INDEX__) and shows a
 * keyboard-navigable dropdown of tools, jobs and trades. No dependencies, no network
 * requests, no indexed result pages: the query never leaves the page and never enters
 * the URL, so crawlers cannot build thin /search/ pages out of it.
 *
 * Progressive enhancement: if JS is off (or the index failed to load) the form is
 * simply inert and the rest of the page works exactly as before.
 */
(function () {
  var form = document.getElementById('site-search');
  var idx = window.__TS_INDEX__;
  if (!form || !idx || !idx.length) return;

  var input = form.querySelector('input[type="search"]');
  var panel = form.querySelector('.search-results');
  if (!input || !panel) return;

  var GROUPS = [
    { key: 'tool', label: 'Tools' },
    { key: 'job', label: 'Jobs' },
    { key: 'trade', label: 'Trades' }
  ];
  var PER_GROUP = 6;

  var items = [];
  var active = -1;

  function norm(s) { return String(s || '').toLowerCase(); }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // wrap every occurrence of any search term in <mark>, escaping the rest
  function mark(text, terms) {
    var src = String(text == null ? '' : text);
    var lower = src.toLowerCase();
    var hits = [];

    terms.forEach(function (t) {
      if (!t) return;
      var from = 0, i;
      while ((i = lower.indexOf(t, from)) !== -1) {
        hits.push([i, i + t.length]);
        from = i + t.length;
      }
    });
    if (!hits.length) return esc(src);

    hits.sort(function (a, b) { return a[0] - b[0]; });
    var merged = [hits[0]];
    for (var k = 1; k < hits.length; k++) {
      var last = merged[merged.length - 1];
      if (hits[k][0] <= last[1]) last[1] = Math.max(last[1], hits[k][1]);
      else merged.push(hits[k]);
    }

    var out = '', pos = 0;
    merged.forEach(function (h) {
      out += esc(src.slice(pos, h[0])) + '<mark>' + esc(src.slice(h[0], h[1])) + '</mark>';
      pos = h[1];
    });
    return out + esc(src.slice(pos));
  }

  // name prefix > name substring (earlier is better) > keywords > description
  function scoreTerm(rec, q) {
    var n = norm(rec.n);
    var i = n.indexOf(q);
    if (i === 0) return 1000 - n.length;
    if (i > 0) return 700 - i * 10;
    if (norm(rec.k).indexOf(q) !== -1) return 300;
    if (norm(rec.d).indexOf(q) !== -1) return 100;
    return 0;
  }

  // every term must hit somewhere (AND); score is the sum
  function query(raw) {
    var terms = norm(raw).split(/\s+/).filter(Boolean);
    if (!terms.length) return [];

    var out = [];
    for (var i = 0; i < idx.length; i++) {
      var rec = idx[i], total = 0, ok = true;
      for (var j = 0; j < terms.length; j++) {
        var s = scoreTerm(rec, terms[j]);
        if (!s) { ok = false; break; }
        total += s;
      }
      if (ok) out.push({ rec: rec, score: total });
    }
    out.sort(function (a, b) {
      if (b.score !== a.score) return b.score - a.score;
      return a.rec.n.localeCompare(b.rec.n);
    });
    return out;
  }

  function show() {
    panel.hidden = false;
    input.setAttribute('aria-expanded', 'true');
  }

  function hide() {
    panel.hidden = true;
    input.setAttribute('aria-expanded', 'false');
    if (active > -1 && items[active]) items[active].classList.remove('is-active');
    active = -1;
  }

  function setActive(next) {
    if (!items.length) return;
    if (active > -1 && items[active]) items[active].classList.remove('is-active');
    active = (next + items.length) % items.length;
    items[active].classList.add('is-active');
    if (items[active].scrollIntoView) items[active].scrollIntoView({ block: 'nearest' });
  }

  function render(raw) {
    var terms = norm(raw).split(/\s+/).filter(Boolean);
    if (!terms.length) { hide(); return; }

    var hits = query(raw);
    if (!hits.length) {
      panel.innerHTML = '<p class="search-none">Nothing matched &ldquo;' + esc(raw) +
        '&rdquo;. Try a job like <em>quoting</em>, a trade like <em>plumbers</em>, ' +
        'or a tool name.</p>';
      items = [];
      active = -1;
      show();
      return;
    }

    var html = '';
    GROUPS.forEach(function (g) {
      var rows = hits.filter(function (h) { return h.rec.t === g.key; }).slice(0, PER_GROUP);
      if (!rows.length) return;
      html += '<div class="search-group"><span class="search-group-label">' + esc(g.label) + '</span>';
      rows.forEach(function (h) {
        html += '<a class="search-item" role="option" href="' + esc(h.rec.u) + '">' +
                  '<span class="search-item-name">' + mark(h.rec.n, terms) + '</span>' +
                  '<span class="search-item-desc">' + mark(h.rec.d, terms) + '</span>' +
                '</a>';
      });
      html += '</div>';
    });

    panel.innerHTML = html;
    items = Array.prototype.slice.call(panel.querySelectorAll('.search-item'));
    active = -1;
    show();
  }

  input.addEventListener('input', function () { render(input.value); });

  input.addEventListener('focus', function () {
    if (input.value.trim()) render(input.value);
  });

  input.addEventListener('keydown', function (e) {
    if (e.key === 'ArrowDown') { e.preventDefault(); if (panel.hidden) render(input.value); setActive(active + 1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActive(active - 1); }
    else if (e.key === 'Enter') {
      if (active > -1 && items[active]) { e.preventDefault(); items[active].click(); }
      else if (items.length === 1) { e.preventDefault(); items[0].click(); }
      else e.preventDefault(); // never let the form write ?q= into the URL
    } else if (e.key === 'Escape') {
      if (!panel.hidden) { e.preventDefault(); hide(); }
    }
  });

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    if (active > -1 && items[active]) items[active].click();
    else if (items.length) items[0].click();
  });

  document.addEventListener('click', function (e) {
    if (!form.contains(e.target)) hide();
  });
})();
