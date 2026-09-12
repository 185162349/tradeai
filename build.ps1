# TradeStack site generator
# Reads src/*.json + src/templates/*.html and writes a static site into dist/
# Run:  powershell -ExecutionPolicy Bypass -File .\build.ps1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $root 'src'
$dist = Join-Path $root 'dist'

# ----------------------------------------------------------------- helpers

function Read-JsonFile($path) {
  return (Get-Content $path -Raw -Encoding UTF8) | ConvertFrom-Json
}

function Write-Page($relPath, $html) {
  $full = Join-Path $dist ($relPath -replace '/', [IO.Path]::DirectorySeparatorChar)
  # a path with no file extension is treated as a directory and gets index.html
  if ($full -notmatch '\.[A-Za-z0-9]+$') { $full = Join-Path $full 'index.html' }
  $dir = Split-Path -Parent $full
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, $html, $enc)
}

function Esc($s) {
  if ($null -eq $s) { return '' }
  return [System.Net.WebUtility]::HtmlEncode([string]$s)
}

# escapes a value for use inside a JSON string literal
function JsStr($s) {
  if ($null -eq $s) { return '' }
  $t = [string]$s
  $t = $t -replace '\\', '\\'
  $t = $t -replace '"', '\"'
  $t = $t -replace "`r`n", ' '
  $t = $t -replace "`n", ' '
  return $t.Trim()
}

function Apply($tpl, $tokens) {
  $out = $tpl
  foreach ($k in $tokens.Keys) {
    $out = $out.Replace('{{' + $k + '}}', [string]$tokens[$k])
  }
  return $out
}

function Get-Hostname($url) {
  try {
    $u = [System.Uri]$url
    return ($u.Host -replace '^www\.', '')
  } catch { return $url }
}

function Build-Page($contentHtml, $title, $description, $canonical, $jsonld) {
  $layout = Get-Content (Join-Path $src 'templates\layout.html') -Raw -Encoding UTF8
  $tokens = @{
    'TITLE'       = Esc $title
    'DESCRIPTION' = Esc $description
    'CANONICAL'   = $canonical
    'JSONLD'      = $jsonld
    'CONTENT'     = $contentHtml
    'SITE_NAME'   = Esc $script:cfg.siteName
    'DOMAIN'      = $script:cfg.domain
    'YEAR'        = (Get-Date).Year
    'TAGLINE'     = Esc $script:cfg.tagline
    'NAV'         = $script:navHtml
  }
  return Apply $layout $tokens
}

function Jsonld($objectText) {
  return "<script type=`"application/ld+json`">`n" + $objectText + "`n</script>"
}

# ----------------------------------------------------------------- load data

$cfg       = Read-JsonFile (Join-Path $src 'config.json')
$tax       = Read-JsonFile (Join-Path $src 'taxonomy.json')
$toolsJson = Read-JsonFile (Join-Path $src 'tools.json')
$pagesJson = Read-JsonFile (Join-Path $src 'pages.json')

$tools      = @($toolsJson.tools)
$tasks      = @($tax.tasks)
$trades     = @($tax.trades)
$pricingNote = $toolsJson.pricingNote

$taskBySlug = @{}
foreach ($t in $tasks) { $taskBySlug[$t.slug] = $t }

$tradeBySlug = @{}
foreach ($tr in @($tax.trades)) { $tradeBySlug[$tr.slug] = $tr.name }

# long-form descriptions: slug -> text
$aboutMap = @{}
$aboutPath = Join-Path $src 'tool-about.json'
if (Test-Path $aboutPath) {
  $aboutObj = Read-JsonFile $aboutPath
  foreach ($prop in $aboutObj.PSObject.Properties) { $aboutMap[$prop.Name] = $prop.Value }
}

$toolsByTask = @{}
foreach ($t in $tasks) { $toolsByTask[$t.slug] = New-Object System.Collections.ArrayList }
foreach ($tool in $tools) {
  foreach ($ts in @($tool.tasks)) {
    if ($toolsByTask.ContainsKey($ts)) { [void]$toolsByTask[$ts].Add($tool) }
  }
}

$tplHome = Get-Content (Join-Path $src 'templates\home.html')   -Raw -Encoding UTF8
$tplTool = Get-Content (Join-Path $src 'templates\tool.html')   -Raw -Encoding UTF8
$tplTask = Get-Content (Join-Path $src 'templates\task.html')   -Raw -Encoding UTF8
$tplPage = Get-Content (Join-Path $src 'templates\page.html')   -Raw -Encoding UTF8

# shared navigation
$navParts = @()
foreach ($t in ($tasks | Select-Object -First 4)) {
  $navParts += '<a href="/' + $t.slug + '/">' + (Esc $t.name) + '</a>'
}
$navParts += '<a href="/about/">About</a>'
$script:navHtml = $navParts -join "`n      "
$script:cfg = $cfg

# ----------------------------------------------------------------- reset dist

if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$urls = New-Object System.Collections.ArrayList

# ----------------------------------------------------------------- home page

$taskCards = @()
foreach ($t in $tasks) {
  $count = @($toolsByTask[$t.slug]).Count
  $taskCards += '<li><a href="/' + $t.slug + '/">' + (Esc $t.name) +
                '<span>' + (Esc $t.desc) + '</span>' +
                '<span>' + $count + ' tools</span></a></li>'
}

$tradeCards = @()
foreach ($tr in $trades) {
  $short = [string]$tr.context
  if ($short.Length -gt 100) { $short = $short.Substring(0, 100) + '...' }
  $tradeCards += '<li><a href="/' + $tr.slug + '/">' + (Esc $tr.name) +
                 '<span>' + (Esc $short) + '</span></a></li>'
}

$toolItems = @()
foreach ($tool in $tools) {
  $tagParts = @()
  $taskTags = 0
  foreach ($ts in @($tool.tasks)) {
    if ($taskTags -ge 2) { break }
    if ($taskBySlug.ContainsKey($ts)) {
      $tagParts += '<span class="tag">' + (Esc $taskBySlug[$ts].name) + '</span>'
      $taskTags++
    }
  }
  if ($tool.free -match 'Free tier') { $tagParts += '<span class="tag free">Free tier</span>' }
  if ($tool.pricing -notmatch '^\s*Free') {
    $tagParts += '<span class="tag price">' + (Esc $tool.pricing) + '</span>'
  }
  $toolItems += '<li><h3><a href="/tools/' + $tool.slug + '/">' + (Esc $tool.name) + '</a></h3>' +
                '<p>' + (Esc $tool.tagline) + '</p>' +
                '<div class="tags">' + ($tagParts -join '') + '</div></li>'
}

$homeContent = Apply $tplHome @{
  'H1'         = Esc ('AI tools for ' + $cfg.niche)
  'LEAD'       = Esc $cfg.description
  'TOOL_COUNT' = $tools.Count
  'TASK_COUNT' = $tasks.Count
  'TRADE_COUNT' = $trades.Count
  'UPDATED'    = Esc $cfg.lastUpdated
  'TASK_CARDS' = ($taskCards -join "`n      ")
  'TRADE_CARDS' = ($tradeCards -join "`n      ")
  'TOOL_LIST'  = ($toolItems -join "`n      ")
}

$homeJsonld = Jsonld ('{
  "@context": "https://schema.org",
  "@type": "WebSite",
  "name": "' + $cfg.siteName + '",
  "url": "' + $cfg.domain + '/",
  "description": "' + $cfg.description + '"
}')

$html = Build-Page $homeContent ('AI tools for ' + $cfg.niche) $cfg.description ($cfg.domain + '/') $homeJsonld
Write-Page 'index.html' $html
[void]$urls.Add($cfg.domain + '/')

# ----------------------------------------------------------------- task pages

foreach ($t in $tasks) {
  $list = @()
  foreach ($tool in @($toolsByTask[$t.slug])) {
    $tagParts = @()
    if ($tool.free -match 'Free tier') { $tagParts += '<span class="tag free">Free tier</span>' }
    $tagParts += '<span class="tag">' + (Esc $tool.pricing) + '</span>'
    $list += '<li><h3><a href="/tools/' + $tool.slug + '/">' + (Esc $tool.name) + '</a></h3>' +
             '<p>' + (Esc $tool.tagline) + '</p>' +
             '<div class="tags">' + ($tagParts -join '') + '</div></li>'
  }

  $otherCards = @()
  foreach ($other in $tasks) {
    if ($other.slug -eq $t.slug) { continue }
    $otherCards += '<li><a href="/' + $other.slug + '/">' + (Esc $other.name) +
                   '<span>' + @($toolsByTask[$other.slug]).Count + ' tools</span></a></li>'
  }

  $content = Apply $tplTask @{
    'NAME'        = Esc $t.name
    'H1'          = Esc ($t.name + ' - AI tools for contractors')
    'DESC'        = Esc $t.desc
    'PAIN'        = Esc $t.pain
    'TOOL_LIST'   = ($list -join "`n      ")
    'OTHER_TASKS' = ($otherCards -join "`n      ")
  }

  $canonical = $cfg.domain + '/' + $t.slug + '/'
  $title = $t.name + ' - AI tools for contractors and trades'
  $desc  = $t.desc
  $jsonld = Jsonld ('{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "' + $title + '",
  "url": "' + $canonical + '",
  "description": "' + $desc + '"
}')

  $html = Build-Page $content $title $desc $canonical $jsonld
  Write-Page ($t.slug + '/index.html') $html
  [void]$urls.Add($canonical)
}

# ----------------------------------------------------------------- tool pages

foreach ($tool in $tools) {
  $primaryTask = @($tool.tasks)[0]
  $primaryName = if ($taskBySlug.ContainsKey($primaryTask)) { $taskBySlug[$primaryTask].name } else { 'Tools' }

  $taskLinks = @()
  foreach ($ts in @($tool.tasks)) {
    if ($taskBySlug.ContainsKey($ts)) {
      $taskLinks += '<a href="/' + $ts + '/">' + (Esc $taskBySlug[$ts].name) + '</a>'
    }
  }

  $tradeNamesRaw = @()
  foreach ($tr in @($tool.trades)) {
    if ($tradeBySlug.ContainsKey($tr)) { $tradeNamesRaw += $tradeBySlug[$tr] } else { $tradeNamesRaw += $tr }
  }

  $tradeLinks = @()
  foreach ($tr in @($tool.trades)) {
    if ($tradeBySlug.ContainsKey($tr)) {
      $tradeLinks += '<a href="/' + $tr + '/">' + (Esc $tradeBySlug[$tr]) + '</a>'
    } else {
      $tradeLinks += Esc $tr
    }
  }

  $aboutText = if ($aboutMap.ContainsKey($tool.slug)) { $aboutMap[$tool.slug] } else { $tool.tagline }
  $whoSuits  = if ($tradeNamesRaw.Count -gt 0) {
    'Built with ' + ($tradeNamesRaw -join ', ') + ' in mind. ' + $tool.bestFor
  } else { $tool.bestFor }

  $prosHtml = @()
  foreach ($p in @($tool.pros)) { $prosHtml += '<li>' + (Esc $p) + '</li>' }
  $consHtml = @()
  foreach ($c in @($tool.cons)) { $consHtml += '<li>' + (Esc $c) + '</li>' }

  $related = @()
  foreach ($other in @($toolsByTask[$primaryTask])) {
    if ($other.slug -eq $tool.slug) { continue }
    $related += '<li><h3><a href="/tools/' + $other.slug + '/">' + (Esc $other.name) + '</a></h3>' +
                '<p>' + (Esc $other.tagline) + '</p></li>'
    if ($related.Count -ge 4) { break }
  }
  if ($related.Count -eq 0) { $related += '<li><p>No other tools in this category yet.</p></li>' }

  $content = Apply $tplTool @{
    'NAME'         = Esc $tool.name
    'TAGLINE'      = Esc $tool.tagline
    'BESTFOR'      = Esc $tool.bestFor
    'PRICING'      = Esc $tool.pricing
    'FREE'         = Esc $tool.free
    'AI'           = Esc $tool.ai
    'URL'          = Esc $tool.url
    'HOST'         = Esc (Get-Hostname $tool.url)
    'TASK_CRUMB'   = '<a href="/' + $primaryTask + '/">' + (Esc $primaryName) + '</a>'
    'TASK_LINKS'   = ($taskLinks -join ', ')
    'TRADE_LINKS'  = ($tradeLinks -join ', ')
    'ABOUT'        = Esc $aboutText
    'WHO_SUITS'    = Esc $whoSuits
    'PROS'         = ($prosHtml -join "`n      ")
    'CONS'         = ($consHtml -join "`n      ")
    'RELATED'      = ($related -join "`n      ")
    'PRICING_NOTE' = Esc $pricingNote
  }

  $canonical = $cfg.domain + '/tools/' + $tool.slug + '/'
  $title = $tool.name + ' - ' + $primaryName + ' for contractors'
  $desc  = $tool.tagline
  $jsonld = Jsonld ('{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "' + $tool.name + '",
  "applicationCategory": "BusinessApplication",
  "operatingSystem": "Web",
  "url": "' + $canonical + '",
  "description": "' + $desc + '"
}')

  $html = Build-Page $content $title $desc $canonical $jsonld
  Write-Page ('tools/' + $tool.slug + '/index.html') $html
  [void]$urls.Add($canonical)
}

# ----------------------------------------------------------------- trade pages

$toolsByTrade = @{}
foreach ($tr in $trades) { $toolsByTrade[$tr.slug] = New-Object System.Collections.ArrayList }
foreach ($tl in $tools) {
  foreach ($tr in @($tl.trades)) {
    if ($toolsByTrade.ContainsKey($tr)) { [void]$toolsByTrade[$tr].Add($tl) }
  }
}

function Count-ForTrade($taskSlug, $tradeSlug) {
  $n = 0
  foreach ($tl in @($toolsByTask[$taskSlug])) {
    if (@($tl.trades) -contains $tradeSlug) { $n++ }
  }
  return $n
}

$tplTrade = Get-Content (Join-Path $src 'templates\trade.html') -Raw -Encoding UTF8

foreach ($tr in $trades) {
  $list = @()
  foreach ($tl in @($toolsByTrade[$tr.slug])) {
    $tagParts = @()
    if ($tl.free -match 'Free tier') { $tagParts += '<span class="tag free">Free tier</span>' }
    $list += '<li><h3><a href="/tools/' + $tl.slug + '/">' + (Esc $tl.name) + '</a></h3>' +
             '<p>' + (Esc $tl.tagline) + '</p>' +
             '<div class="tags">' + ($tagParts -join '') + '</div></li>'
  }

  $cards = @()
  foreach ($t in $tasks) {
    $n = Count-ForTrade $t.slug $tr.slug
    if ($n -eq 0) { continue }
    $cards += '<li><a href="/' + $t.slug + '/' + $tr.slug + '/">' + (Esc $t.name) +
              '<span>' + $n + ' tools for ' + (Esc $tr.name) + '</span></a></li>'
  }

  $content = Apply $tplTrade @{
    'NAME'       = Esc $tr.name
    'H1'         = Esc ('AI tools for ' + $tr.name)
    'CONTEXT'    = Esc $tr.context
    'TASK_CARDS' = ($cards -join "`n      ")
    'TOOL_LIST'  = ($list -join "`n      ")
  }

  $canonical = $cfg.domain + '/' + $tr.slug + '/'
  $title = 'AI tools for ' + $tr.name
  $desc  = [string]$tr.context
  $jsonld = Jsonld ('{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "' + $title + '",
  "url": "' + $canonical + '",
  "description": "' + $desc + '"
}')

  $html = Build-Page $content $title $desc $canonical $jsonld
  Write-Page ($tr.slug + '/index.html') $html
  [void]$urls.Add($canonical)
}

# ----------------------------------------------------------------- task x trade pages

$tplCombo = Get-Content (Join-Path $src 'templates\combination.html') -Raw -Encoding UTF8

foreach ($t in $tasks) {
  foreach ($tr in $trades) {
    $matched = @()
    foreach ($tl in @($toolsByTask[$t.slug])) {
      if (@($tl.trades) -contains $tr.slug) { $matched += $tl }
    }
    if ($matched.Count -lt 2) { continue }

    # unique pain point for this job x trade pair (falls back to the generic job pain)
    $painText = ''
    if ($tr.pains) {
      $painProp = $tr.pains.PSObject.Properties[$t.slug]
      if ($painProp) { $painText = [string]$painProp.Value }
    }
    if (-not $painText) { $painText = [string]$t.pain }

    $list = @()
    $rows = @()
    foreach ($tl in $matched) {
      $tagParts = @()
      if ($tl.free -match 'Free tier') { $tagParts += '<span class="tag free">Free tier</span>' }
      $list += '<li><h3><a href="/tools/' + $tl.slug + '/">' + (Esc $tl.name) + '</a></h3>' +
               '<p>' + (Esc $tl.tagline) + '</p>' +
               '<div class="tags">' + ($tagParts -join '') + '</div></li>'

      $best = [string]$tl.bestFor
      if ($best.Length -gt 95) { $best = $best.Substring(0, 92).TrimEnd() + '...' }
      $rows += '<tr><td><a href="/tools/' + $tl.slug + '/">' + (Esc $tl.name) + '</a></td>' +
               '<td>' + (Esc $best) + '</td>' +
               '<td>' + (Esc $tl.pricing) + '</td>' +
               '<td>' + (Esc $tl.free) + '</td></tr>'
    }

    $compareTable = '<div class="table-scroll"><table class="compare">' +
      '<thead><tr><th>Tool</th><th>Best for</th><th>Pricing</th><th>Free option</th></tr></thead>' +
      '<tbody>' + ($rows -join "`n      ") + '</tbody></table></div>'

    $other = @()
    foreach ($ot in $tasks) {
      if ($ot.slug -eq $t.slug) { continue }
      $n = Count-ForTrade $ot.slug $tr.slug
      if ($n -lt 2) { continue }
      $other += '<li><a href="/' + $ot.slug + '/' + $tr.slug + '/">' + (Esc $ot.name) +
                '<span>' + $n + ' tools</span></a></li>'
    }

    $tradeLower = ([string]$tr.name).ToLower()
    if ($tr.slug -eq 'hvac') { $tradeLower = 'HVAC' }   # acronym, do not lowercase
    $taskLower  = ([string]$t.name).ToLower()

    $comboDesc = 'Tools that help ' + $tradeLower + ' with ' + $taskLower + '. ' + $t.desc

    # ---- FAQ: two answers built from the page data, the unique pain, plus the trade's own question
    $topText = @()
    foreach ($tl in @($matched | Select-Object -First 3)) {
      $bf = ([string]$tl.bestFor) -replace '\.$', ''
      $topText += $tl.name + ' (' + $bf + ')'
    }
    $freeCount = @(@($matched) | Where-Object { $_.free -match 'Free tier' }).Count

    $faq = New-Object System.Collections.ArrayList
    [void]$faq.Add(@{
      q = 'Which ' + $taskLower + ' tools work best for ' + $tradeLower + '?'
      a = 'The three that fit best here are ' + ($topText -join ', ') +
          '. Start with the one whose description matches your crew size, not the one with the longest feature list.'
    })
    [void]$faq.Add(@{
      q = 'How much does ' + $taskLower + ' software cost for ' + $tradeLower + '?'
      a = 'Across the ' + $matched.Count + ' tools on this page, ' + $freeCount +
          ' have a free tier and the rest are paid, most of them billed per user per month. Prices change often, so treat the figures here as indicative and confirm on the vendor site.'
    })
    [void]$faq.Add(@{
      q = 'Why does ' + $taskLower + ' cause problems for ' + $tradeLower + ' specifically?'
      a = $painText
    })
    if ($tr.faq -and $tr.faq.q) {
      [void]$faq.Add(@{ q = [string]$tr.faq.q; a = [string]$tr.faq.a })
    }

    $faqHtml = @()
    $faqSchema = @()
    $firstFaq = $true
    foreach ($f in $faq) {
      $openAttr = if ($firstFaq) { ' open' } else { '' }
      $faqHtml += '<details class="faq-item"' + $openAttr + '><summary>' + (Esc $f.q) + '</summary>' +
                  '<p class="faq-a">' + (Esc $f.a) + '</p></details>'
      $faqSchema += '{"@type":"Question","name":"' + (JsStr $f.q) +
                    '","acceptedAnswer":{"@type":"Answer","text":"' + (JsStr $f.a) + '"}}'
      $firstFaq = $false
    }

    $content = Apply $tplCombo @{
      'TRADE_SLUG'    = $tr.slug
      'TRADE_NAME'    = Esc $tr.name
      'TASK_NAME'     = Esc $t.name
      'H1'            = Esc ($t.name + ' tools for ' + $tr.name)
      'DESC'          = Esc $comboDesc
      'PAIN'          = Esc $painText
      'CONTEXT'       = Esc $tr.context
      'COMPARE_TABLE' = $compareTable
      'TOOL_LIST'     = ($list -join "`n      ")
      'FAQ_ITEMS'     = ($faqHtml -join "`n      ")
      'OTHER_TASKS'   = ($other -join "`n      ")
    }

    $canonical = $cfg.domain + '/' + $t.slug + '/' + $tr.slug + '/'
    $title = $t.name + ' tools for ' + $tr.name
    $pageJsonld = Jsonld ('{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "' + $title + '",
  "url": "' + $canonical + '",
  "description": "' + $comboDesc + '"
}')
    $faqJsonld = Jsonld ('{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    ' + ($faqSchema -join ",`n    ") + '
  ]
}')
    $jsonld = $pageJsonld + "`n" + $faqJsonld

    $html = Build-Page $content $title $comboDesc $canonical $jsonld
    Write-Page ($t.slug + '/' + $tr.slug + '/index.html') $html
    [void]$urls.Add($canonical)
  }
}

# ----------------------------------------------------------------- static pages

foreach ($p in @($pagesJson.pages)) {
  $body = $p.body -replace '\{\{CONTACT_EMAIL\}\}', $cfg.contactEmail
  $content = Apply $tplPage @{ 'H1' = Esc $p.title; 'BODY' = $body }
  $canonical = $cfg.domain + '/' + $p.slug + '/'
  $html = Build-Page $content ($p.title + ' - ' + $cfg.siteName) $p.description $canonical ''
  Write-Page ($p.slug + '/index.html') $html
  [void]$urls.Add($canonical)
}

# ----------------------------------------------------------------- sitemap / robots / llms

$sitemap = '<?xml version="1.0" encoding="UTF-8"?>' + "`n" +
           '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + "`n"
foreach ($u in $urls) {
  $sitemap += '  <url><loc>' + $u + '</loc></url>' + "`n"
}
$sitemap += '</urlset>'
Write-Page 'sitemap.xml' $sitemap

$robots = "User-agent: *`nAllow: /`n`nSitemap: " + $cfg.domain + "/sitemap.xml"
Write-Page 'robots.txt' $robots

$llms = New-Object System.Text.StringBuilder
[void]$llms.AppendLine('# ' + $cfg.siteName)
[void]$llms.AppendLine('')
[void]$llms.AppendLine('> ' + $cfg.description)
[void]$llms.AppendLine('')
[void]$llms.AppendLine('## Jobs')
[void]$llms.AppendLine('')
foreach ($t in $tasks) {
  [void]$llms.AppendLine('- [' + $t.name + '](' + $cfg.domain + '/' + $t.slug + '/): ' + $t.desc)
}
[void]$llms.AppendLine('')
[void]$llms.AppendLine('## Tools')
[void]$llms.AppendLine('')
foreach ($tool in $tools) {
  [void]$llms.AppendLine('- [' + $tool.name + '](' + $cfg.domain + '/tools/' + $tool.slug + '/): ' + $tool.tagline)
}
Write-Page 'llms.txt' $llms.ToString()

# ----------------------------------------------------------------- assets

$assetsSrc  = Join-Path $src 'assets'
$assetsDest = Join-Path $dist 'assets'
if (Test-Path $assetsSrc) {
  Copy-Item $assetsSrc $assetsDest -Recurse -Force
}

# ----------------------------------------------------------------- static extras

$staticDir = Join-Path $src 'static'
if (Test-Path $staticDir) {
  Copy-Item (Join-Path $staticDir '*') $dist -Recurse -Force
}

$notFoundContent = '<main class="page"><div class="wrap"><h1>Page not found</h1>' +
                   '<p>The page you were looking for does not exist. Start from the ' +
                   '<a href="/">directory home</a>.</p></div></main>'
$notFound = Build-Page $notFoundContent 'Page not found' 'The page you were looking for does not exist.' ($cfg.domain + '/404.html') ''
Write-Page '404.html' $notFound

Write-Host ('Done. Pages: ' + $urls.Count + '  ->  ' + $dist) -ForegroundColor Green
