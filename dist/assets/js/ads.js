/*
 * AdSense configuration.
 *
 * The site ships with advertising disabled. Once AdSense approves the domain:
 *   1. set enabled to true
 *   2. replace client with your ca-pub- ID
 *   3. replace the slot IDs with the ad unit IDs you create in AdSense
 *   4. run build.ps1 again and redeploy
 *
 * Any .ad-slot element whose data-ad name is not in `slots` stays empty and is
 * hidden by CSS, so nothing breaks while advertising is off.
 */
window.SITE_ADS = {
  enabled: false,
  client: 'ca-pub-0000000000000000',
  slots: {
    header: '0000000000',
    footer: '0000000000'
  }
};

(function () {
  var cfg = window.SITE_ADS;
  if (!cfg || !cfg.enabled || !cfg.client || cfg.client.indexOf('0000000000000000') !== -1) return;

  var script = document.createElement('script');
  script.async = true;
  script.src =
    'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=' +
    encodeURIComponent(cfg.client);
  script.crossOrigin = 'anonymous';
  document.head.appendChild(script);

  function mount(el) {
    var name = el.getAttribute('data-ad');
    var slot = cfg.slots[name];
    if (!slot || slot === '0000000000') return;

    var ins = document.createElement('ins');
    ins.className = 'adsbygoogle';
    ins.style.display = 'block';
    ins.setAttribute('data-ad-client', cfg.client);
    ins.setAttribute('data-ad-slot', slot);
    ins.setAttribute('data-ad-format', 'auto');
    ins.setAttribute('data-full-width-responsive', 'true');
    el.appendChild(ins);

    (window.adsbygoogle = window.adsbygoogle || []).push({});
  }

  function mountAll() {
    var slots = document.querySelectorAll('.ad-slot');
    for (var i = 0; i < slots.length; i++) mount(slots[i]);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mountAll);
  } else {
    mountAll();
  }
})();
