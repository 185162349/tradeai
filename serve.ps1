# Minimal static file server for local preview of dist/
# Run:  powershell -ExecutionPolicy Bypass -File .\serve.ps1
# Then open http://localhost:8080/

param([int]$Port = 8080)

$root = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'dist'

if (-not (Test-Path $root)) {
  Write-Host "dist/ not found. Run build.ps1 first." -ForegroundColor Red
  exit 1
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

try {
  $listener.Start()
} catch {
  Write-Host "Could not start on port $Port. Try a different port: -Port 8081" -ForegroundColor Red
  exit 1
}

Write-Host "Serving $root" -ForegroundColor Green
Write-Host "Open http://localhost:$Port/   (Ctrl+C to stop)" -ForegroundColor Green

$types = @{
  '.html' = 'text/html; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.xml'  = 'application/xml; charset=utf-8'
  '.txt'  = 'text/plain; charset=utf-8'
  '.svg'  = 'image/svg+xml'
  '.ico'  = 'image/x-icon'
}

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = $ctx.Request.Url.LocalPath
  if ($path -eq '/' -or $path -eq '') { $path = '/index.html' }

  $file = Join-Path $root ($path.TrimStart('/') -replace '/', '\')
  if (Test-Path $file -PathType Container) { $file = Join-Path $file 'index.html' }

  if (Test-Path $file -PathType Leaf) {
    $ext = [System.IO.Path]::GetExtension($file)
    $ctx.Response.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
    $bytes = [System.IO.File]::ReadAllBytes($file)
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  } else {
    $ctx.Response.StatusCode = 404
    $notFound = Join-Path $root '404.html'
    if (Test-Path $notFound) {
      $ctx.Response.ContentType = 'text/html; charset=utf-8'
      $bytes = [System.IO.File]::ReadAllBytes($notFound)
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    }
  }
  $ctx.Response.Close()
}
