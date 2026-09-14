# TradeStack — AI tools directory for contractors & trades1

A static, data-driven directory of AI tools for contractors and trade businesses, organised by
**occupation × job** rather than by tool category. Built to be regenerated from JSON: adding a tool,
a job or a trade adds pages automatically.

## Output size

94 pages from current data:

| Section | Pages |
|---|---|
| Home | 1 |
| Job pages (`/quoting/`) | 7 |
| Trade pages (`/plumbers/`) | 7 |
| Tool pages (`/tools/housecall-pro/`) | 32 |
| Job × trade pages (`/quoting/plumbers/`) | 43 |
| Static pages (about, privacy, terms, contact) | 4 |
| Plus `sitemap.xml`, `robots.txt`, `llms.txt`, `404.html`, `_headers` | — |

Job × trade pages are only generated when at least **2 tools** match, so no page is created empty
or near-empty.

## Build

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

Output goes to `dist/`. The script wipes `dist/` first, so it is always a clean build.

## Deploy to Cloudflare Pages

1. Push this folder to a GitHub repository, **or** just keep it locally.
2. In the Cloudflare dashboard: **Workers & Pages → Create → Pages**.
3. Either connect the repository (build command: leave empty, output directory: `dist`)
   or drag-and-drop the `dist` folder directly.
4. Add your custom domain under the project's **Custom domains** tab.
5. Submit `https://yourdomain.com/sitemap.xml` in Google Search Console.
   Also submit to Bing Webmaster (it supports IndexNow for near-instant indexing).

## Configure the site

Edit `src/config.json`:

| Field | Meaning |
|---|---|
| `siteName` | Brand name shown in the header and titles |
| `domain` | Full base URL including `https://` — used for canonical tags, sitemap and JSON-LD |
| `description` | Site meta description |
| `contactEmail` | Shown on the contact page |

Then rebuild. **Change `domain` before going live** — otherwise canonical tags will point at the placeholder.

## Turn on advertising

Advertising is off in the shipped build, so nothing renders and no third-party script loads.

1. Get AdSense approval for the domain (expect to need 20+ substantive pages — this build has 90+).
2. Edit `src/assets/js/ads.js`:
   - set `enabled: true`
   - replace `client` with your `ca-pub-…` ID
   - create ad units in AdSense and paste their slot IDs into `slots`
3. Rebuild and redeploy.

Two ad positions are already wired: `header` (mid-content) and `footer` (below content).
Any slot without a configured ID stays empty and is hidden by CSS, so there is no broken layout.

Google requires a certified consent management platform (CMP) for serving ads to EEA/UK users.
AdSense includes a free one under **Privacy & messaging** — enable it before you get European traffic.

## Adding content

| To add | Edit | Result |
|---|---|---|
| A tool | `src/tools.json` (+ long description in `src/tool-about.json`) | New `/tools/{slug}/` page, listed on matching job/trade pages |
| A job | `tasks` array in `src/taxonomy.json` | New job page + job × trade pages |
| A trade | `trades` array in `src/taxonomy.json` | New trade page + job × trade pages |
| A static page | `src/pages.json` | New top-level page |

Then run `build.ps1`.

Every tool needs a `slug`, `name`, `url`, `tagline`, `tasks`, `trades`, `pricing`, `free`,
`bestFor`, `ai`, `pros`, `cons`. Write the long description into `tool-about.json` keyed by slug —
if it is missing, the tagline is used instead and the page will read thin.

## Structure

```
tradeai/
├── build.ps1              generator
├── src/
│   ├── config.json        brand + domain
│   ├── taxonomy.json      jobs and trades
│   ├── tools.json         tool records
│   ├── tool-about.json    long descriptions, keyed by tool slug
│   ├── pages.json         about / privacy / terms / contact
│   ├── templates/         layout, home, task, trade, tool, combination, page
│   ├── static/            copied verbatim into dist (e.g. _headers)
│   └── assets/            css + js
└── dist/                  generated site (deploy this)
```

## On-site search

The home page has an instant search box. `build.ps1` generates `dist/assets/js/search-index.js`
(~10 KB, one cached file) from the same JSON, and `src/assets/js/search.js` does the matching in
the browser: name prefix → name substring → keywords (jobs, trades, pricing) → description.
Results are grouped into Tools / Jobs / Trades and are keyboard navigable.

It is deliberately **not** a crawlable search: the query never reaches the URL, so no thin
`/search/?q=…` pages can be indexed. `robots.txt` blocks `/*?q=` as insurance. Nothing needs to
change when you add tools — the index is rebuilt from `tools.json` / `taxonomy.json`.

### Search analytics

`search.js` emits two events, 1.2 s after typing stops and only for queries of 3+ characters:

| Event | Properties | Meaning |
|---|---|---|
| `search` | `query`, `hits` | What people look for. `hits: 0` is the useful one — demand you have no page for. |
| `search-click` | `query`, `target` | Which result actually won the click. |

It reports to Umami, Plausible or a `dataLayer` (GA4) — whichever exists on `window`. Nothing is
sent if none is installed, so the shipping build stays script-free. To switch it on, add one
script tag to `templates/layout.html` where the comment marks it:

```html
<script defer src="https://cloud.umami.is/script.js" data-website-id="YOUR-ID"></script>
```

**Note:** Cloudflare Web Analytics (the free, cookieless one) does **not** support custom events —
it only measures pageviews, referrers and countries. Search terms cannot land there, so you need
a second, still-cookieless script (Umami or Plausible) if you want to see them.

## Notes on content quality

- Google penalises programmatic pages that are near-duplicates ("doorway pages"). Two guards are
  in place: job × trade pages require ≥2 matching tools, and every trade carries its own written
  `context` paragraph so the pages are not templated copies of each other.
- Tool descriptions include an explicit "Where the AI actually is" section. Several tools listed
  have little or no AI — saying so plainly is deliberate and is a trust signal.
- Prices change often. Each tool page carries a disclaimer pointing to the vendor's own site.
