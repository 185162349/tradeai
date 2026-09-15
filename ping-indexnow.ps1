# Submits every URL in dist/sitemap.xml to IndexNow (Bing, Yandex, Seznam, Naver, Yep).
#
# IndexNow is an open ping protocol: you tell participating engines "these URLs
# changed", and they prioritise crawling them. It is NOT a ranking signal and it
# does NOT reach Google — Google has never adopted the protocol. Its value here
# is first-crawl speed on Bing, which in turn is one of the sources behind
# ChatGPT / Copilot web search.
#
# IMPORTANT: run this only AFTER deploying dist/. The engines fetch
# https://<host>/<key>.txt to verify ownership, so pinging before the key file is
# live returns 403 and the submission is silently dropped.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\ping-indexnow.ps1
#   powershell -ExecutionPolicy Bypass -File .\ping-indexnow.ps1 -WhatIf   # dry run, prints the payload
#
# https://www.indexnow.org/documentation

param(
  # print the request instead of sending it
  [switch]$WhatIf,
  # only submit the first N URLs; useful when testing
  [int]$Limit = 0
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $root 'src'
$dist = Join-Path $root 'dist'

# ------------------------------------------------------------------ key

$keyPath = Join-Path $src 'indexnow.json'
if (-not (Test-Path $keyPath)) {
  Write-Host 'src/indexnow.json not found. Run build.ps1 first — it generates the key.' -ForegroundColor Red
  exit 1
}
try {
  $key = [string](Get-Content $keyPath -Raw -Encoding UTF8 | ConvertFrom-Json).key
} catch {
  Write-Host ('Could not parse src/indexnow.json: ' + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
if (-not $key) {
  Write-Host 'src/indexnow.json contains no key. Delete the file and re-run build.ps1.' -ForegroundColor Red
  exit 1
}

# ------------------------------------------------------------------ host + urls

$cfgPath = Join-Path $src 'config.json'
if (-not (Test-Path $cfgPath)) {
  Write-Host 'src/config.json not found.' -ForegroundColor Red
  exit 1
}
$cfg      = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$siteHost = ([System.Uri]$cfg.domain).Host

$sitemapPath = Join-Path $dist 'sitemap.xml'
if (-not (Test-Path $sitemapPath)) {
  Write-Host 'dist/sitemap.xml not found. Run build.ps1 first.' -ForegroundColor Red
  exit 1
}

$urls = @(
  [regex]::Matches((Get-Content $sitemapPath -Raw), '(?<=<loc>)[^<]+(?=</loc>)') |
    ForEach-Object { $_.Value }
)

# a URL from a different host makes the whole batch fail with 422
$foreign = @($urls | Where-Object { ([System.Uri]$_).Host -ne $siteHost })
if ($foreign.Count -gt 0) {
  Write-Host ('Aborting: ' + $foreign.Count + ' sitemap URL(s) point at another host (e.g. ' +
              $foreign[0] + '). IndexNow rejects the entire batch if any URL is off-host.') -ForegroundColor Red
  exit 1
}

if ($Limit -gt 0 -and $urls.Count -gt $Limit) { $urls = $urls[0..($Limit - 1)] }

if ($urls.Count -eq 0) {
  Write-Host 'No URLs found in the sitemap.' -ForegroundColor Red
  exit 1
}

$keyLocation = 'https://' + $siteHost + '/' + $key + '.txt'

$payload = @{
  host        = $siteHost
  key         = $key
  keyLocation = $keyLocation
  urlList     = @($urls)
} | ConvertTo-Json -Depth 5

# ------------------------------------------------------------------ send

Write-Host ('Host        : ' + $siteHost) -ForegroundColor DarkGray
Write-Host ('Key file    : ' + $keyLocation) -ForegroundColor DarkGray
Write-Host ('URLs        : ' + $urls.Count) -ForegroundColor DarkGray
Write-Host ''

if ($WhatIf) {
  Write-Host '--- dry run, payload would be ---' -ForegroundColor Yellow
  Write-Host $payload
  exit 0
}

# the key file must already be reachable, otherwise every engine returns 403
Write-Host 'Checking the key file is live...' -NoNewline
try {
  $probe = Invoke-WebRequest -Uri $keyLocation -UseBasicParsing -TimeoutSec 20
  $served = ($probe.Content -as [string]).Trim()
  if ($served -ne $key) {
    Write-Host ''
    Write-Host ('The key file is live but its contents do not match (' + $served + '). ' +
                'Deploy dist/ and retry.') -ForegroundColor Red
    exit 1
  }
  Write-Host ' OK' -ForegroundColor Green
} catch {
  Write-Host ''
  Write-Host ('Could not fetch ' + $keyLocation + ' (' + $_.Exception.Message + ').') -ForegroundColor Red
  Write-Host 'Deploy dist/ first — IndexNow verifies ownership by downloading this file.' -ForegroundColor Yellow
  exit 1
}

$endpoints = @(
  @{ name = 'IndexNow (all engines)'; url = 'https://api.indexnow.org/indexnow' }
  # Bing also accepts a direct submit; keeping it as a second endpoint costs one
  # request and covers the case where the shared endpoint is rate limiting.
  @{ name = 'Bing';                   url = 'https://www.bing.com/indexnow' }
)

foreach ($ep in $endpoints) {
  Write-Host ('Submitting to ' + $ep.name + '...') -NoNewline
  try {
    $resp = Invoke-WebRequest -Uri $ep.url -Method Post -UseBasicParsing -TimeoutSec 60 `
              -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload))
    $code = [int]$resp.StatusCode
    if ($code -ge 200 -and $code -lt 300) {
      Write-Host (' accepted (' + $code + ')') -ForegroundColor Green
    } else {
      Write-Host (' returned ' + $code) -ForegroundColor Yellow
    }
  } catch {
    $status = $null
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    switch ($status) {
      400 { Write-Host ' 400 — malformed request. Check the JSON.' -ForegroundColor Red }
      403 { Write-Host ' 403 — key invalid or not found at keyLocation.' -ForegroundColor Red }
      422 { Write-Host ' 422 — a URL does not belong to this host.' -ForegroundColor Red }
      429 { Write-Host ' 429 — rate limited. Wait and retry later.' -ForegroundColor Yellow }
      default { Write-Host (' failed: ' + $_.Exception.Message) -ForegroundColor Red }
    }
  }
}

Write-Host ''
Write-Host 'Done. Bing usually reflects submissions within hours; check Bing Webmaster Tools tomorrow.' -ForegroundColor Cyan
