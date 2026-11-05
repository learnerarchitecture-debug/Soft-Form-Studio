# =============================================================================
# Plush - Soft Form Studio by ArchInsights
# tools/build_rbz.ps1 - packages the plugin and writes the release manifest
# =============================================================================
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\build_rbz.ps1
#   powershell -ExecutionPolicy Bypass -File tools\build_rbz.ps1 -Version 2.0.1
#
# Output:
#   packages\Plush-<version>.rbz   (the distributable SketchUp extension)
#   release.json                   (the update feed consumed by the updater)
#
# Copy the rbz into your browser-free file host and keep release.json at the
# repository root; the updater reads feed -> download -> sha256 verification.
# =============================================================================

param(
  [string]$Version = '',
  [string]$RepoUrl = 'https://raw.githubusercontent.com/learnerarchitecture-debug/Soft-Form-Studio/main'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

# ---------------------------------------------------------------------------
# Version: explicit param, or read it from the loader file
# ---------------------------------------------------------------------------
if ($Version -eq '') {
  $loader = Get-Content (Join-Path $Root 'archinsights_plush.rb') -Raw
  if ($loader -match "VERSION\s*=\s*'([0-9.]+)'") {
    $Version = $Matches[1]
  } else {
    Write-Error 'Could not detect the plugin version from archinsights_plush.rb'
  }
}

# ---------------------------------------------------------------------------
# Staging
# ---------------------------------------------------------------------------
$Stage = Join-Path $env:TEMP ('plush_rbz_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'packages') | Out-Null

$files = @(
  'archinsights_plush.rb',
  'main.rb',
  'core_geometry.rb',
  'fabric_engine.rb',
  'curves.rb',
  'updater.rb',
  'ui.html',
  'ui.css',
  'ui.js',
  'icon.png'
)
foreach ($f in $files) {
  Copy-Item (Join-Path $Root $f) (Join-Path $Stage $f)
}
Copy-Item (Join-Path $Root 'icons') (Join-Path $Stage 'icons') -Recurse -Force

# ---------------------------------------------------------------------------
# Package
# ---------------------------------------------------------------------------
$rbzName = 'Plush-' + $Version + '.rbz'
$rbzPath = Join-Path $Root (Join-Path 'packages' $rbzName)
if (Test-Path $rbzPath) { Remove-Item $rbzPath -Force }
$zipPath = Join-Path $env:TEMP ('plush_' + $Version + '.zip')
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $zipPath
Move-Item $zipPath $rbzPath
Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------
$rbzItem = Get-Item $rbzPath
$size = [long]$rbzItem.Length
$sha256 = (Get-FileHash -Algorithm SHA256 -Path $rbzPath).Hash.ToLower()

$releasedAt = (Get-Date).ToString('yyyy-MM-dd')
$manifest = [ordered]@{
  version      = $Version
  download_url = "$RepoUrl/packages/$rbzName"
  notes        = "Plush $Version - soft form studio for SketchUp."
  released_at  = $releasedAt
  size         = $size
  sha256       = $sha256
}
$json = ($manifest | ConvertTo-Json) -replace "`r`n", "`n"
$json = $json + "`n"
Set-Content -Path (Join-Path $Root 'release.json') -Value $json -Encoding UTF8

Write-Host ("  packaged  " + $rbzPath + "  (" + [math]::Round($size / 1kb, 1) + " KB)")
Write-Host ("  manifest  " + (Join-Path $Root 'release.json'))
Write-Host ('  sha256    ' + $sha256)
Write-Host 'Plush build complete.'
