# =============================================================================
# Plush - Soft Form Studio by ArchInsights
# tools/make_icons.ps1 - renders every toolbar PNG + the product logo with GDI+
# =============================================================================
# Usage:  powershell -ExecutionPolicy Bypass -File tools\make_icons.ps1
# Output: icons\icon_<tool>.png (24 px) + icons\icon_<tool>@2x.png (48 px)
#         icon.png (256 px product logo) + icon.svg (vector twin)
# =============================================================================

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$Root   = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Root 'icons'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Ink     = [System.Drawing.Color]::FromArgb(255, 68, 58, 66)    # warm dark plum
$Accent  = [System.Drawing.Color]::FromArgb(255, 226, 86, 137)  # plush rose
$Accent2 = [System.Drawing.Color]::FromArgb(255, 239, 143, 98)  # soft peach

# ----------------------------------------------------------------------------
# Canvas helpers - all drawing happens in a normalized 0..100 space
# ----------------------------------------------------------------------------
function New-Canvas([int]$Size) {
  $bmp = New-Object System.Drawing.Bitmap([int]$Size, [int]$Size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  @{ G = $g; Bmp = $bmp; Size = $Size }
}

function New-Pen($ctx, $color, [double]$w100) {
  $w = [single]($w100 / 100.0 * $ctx.Size)
  if ($w -lt 0.9) { $w = [single]0.9 }
  $p = New-Object System.Drawing.Pen($color, $w)
  $p.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $p.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $p.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  $p
}

function S([double]$v, [int]$size) { [single]($v / 100.0 * $size) }

function Draw-Line($ctx, $pen, [double[]]$a, [double[]]$b) {
  $s = $ctx.Size
  $ctx.G.DrawLine($pen, (S $a[0] $s), (S $a[1] $s), (S $b[0] $s), (S $b[1] $s))
}

function Draw-Polyline($ctx, $pen, $pts) {
  $s = $ctx.Size
  $converted = New-Object System.Collections.Generic.List[System.Drawing.PointF]
  foreach ($pt in $pts) { $converted.Add((New-Object System.Drawing.PointF((S $pt[0] $s), (S $pt[1] $s)))) }
  $ctx.G.DrawLines($pen, $converted.ToArray())
}

function Draw-Polygon($ctx, $pen, $pts) {
  $s = $ctx.Size
  $converted = New-Object System.Collections.Generic.List[System.Drawing.PointF]
  foreach ($pt in $pts) { $converted.Add((New-Object System.Drawing.PointF((S $pt[0] $s), (S $pt[1] $s)))) }
  $ctx.G.DrawPolygon($pen, $converted.ToArray())
}

function Fill-Polygon($ctx, $brush, $pts) {
  $s = $ctx.Size
  $converted = New-Object System.Drawing.PointF[] $pts.Count
  for ($i = 0; $i -lt $pts.Count; $i++) {
    $converted[$i] = New-Object System.Drawing.PointF((S $pts[$i][0] $s), (S $pts[$i][1] $s))
  }
  $ctx.G.FillPolygon($brush, $converted)
}

function Draw-Ellipse($ctx, $pen, [double]$x, [double]$y, [double]$w, [double]$h) {
  $s = $ctx.Size
  $ctx.G.DrawEllipse($pen, (S $x $s), (S $y $s), (S $w $s), (S $h $s))
}

function Fill-Ellipse($ctx, $brush, [double]$x, [double]$y, [double]$w, [double]$h) {
  $s = $ctx.Size
  $ctx.G.FillEllipse($brush, (S $x $s), (S $y $s), (S $w $s), (S $h $s))
}

function Draw-Arc($ctx, $pen, [double]$x, [double]$y, [double]$w, [double]$h, [double]$start, [double]$sweep) {
  $s = $ctx.Size
  $ctx.G.DrawArc($pen, (S $x $s), (S $y $s), (S $w $s), (S $h $s), [single]$start, [single]$sweep)
}

function Draw-Bezier($ctx, $pen, $pts) {
  $s = $ctx.Size
  $p1 = New-Object System.Drawing.PointF((S $pts[0] $s), (S $pts[1] $s))
  $p2 = New-Object System.Drawing.PointF((S $pts[2] $s), (S $pts[3] $s))
  $p3 = New-Object System.Drawing.PointF((S $pts[4] $s), (S $pts[5] $s))
  $p4 = New-Object System.Drawing.PointF((S $pts[6] $s), (S $pts[7] $s))
  $ctx.G.DrawBezier($pen, $p1, $p2, $p3, $p4)
}

# Rounded rectangle path in 100-space (pillow/mattress/cushion bodies)
function New-RoundRectPath($ctx, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $s = $ctx.Size
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $rx = S $r $s; $ry = S $r $s
  $ax = S $x $s; $ay = S $y $s
  $aw = S $w $s; $ah = S $h $s
  $d = $rx * 2
  $path.AddArc($ax, $ay, $d, $d, 180, 90)
  $path.AddArc($ax + $aw - $d, $ay, $d, $d, 270, 90)
  $path.AddArc($ax + $aw - $d, $ay + $ah - $d, $d, $d, 0, 90)
  $path.AddArc($ax, $ay + $ah - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  $path
}

function Draw-RoundRect($ctx, $pen, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $path = New-RoundRectPath $ctx $x $y $w $h $r
  $ctx.G.DrawPath($pen, $path)
  $path.Dispose()
}

# ----------------------------------------------------------------------------
# Product logo (app icon)
# ----------------------------------------------------------------------------
function Draw-Logo($ctx) {
  $s = $ctx.Size
  $g = $ctx.G
  $bounds = S 3 $s
  $dim = $s - (2 * $bounds)

  # gradient rounded square
  $rectF = New-Object System.Drawing.RectangleF($bounds, $bounds, $dim, $dim)
  $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rectF,
    [System.Drawing.Color]::FromArgb(255, 226, 86, 137),
    [System.Drawing.Color]::FromArgb(255, 242, 162, 92),
    45.0)
  $path = New-RoundRectPath $ctx 3 3 94 94 26
  $g.FillPath($grad, $path)

  # plush stitching: horizontal seam across the middle + cozy smile below
  $white = New-Pen $ctx ([System.Drawing.Color]::FromArgb(255, 255, 250, 246)) 7.0
  Draw-Arc $ctx $white 26 12 48 26 30 120
  Draw-Arc $ctx $white 28 40 44 26 40 100
  $path.Dispose()
  $grad.Dispose()
}

# ----------------------------------------------------------------------------
# Tool glyphs
# ----------------------------------------------------------------------------
$GLYPHS = [ordered]@{

  'corners' = {
    param($ctx, $ink, $accent)
    # big soft corner
    $p = New-Pen $ctx $ink 6.5
    Draw-Arc $ctx $p 20 20 45 45 180 90
    Draw-Line $ctx $p @(20, 65) @(20, 92)
    Draw-Line $ctx $p @(65, 20) @(92, 20)
    # dashed inner guide arc
    $d = New-Pen $ctx $accent 4.2
    $d.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    Draw-Arc $ctx $d 33 33 19 19 180 90
    Draw-Line $ctx $d @(33, 52) @(33, 66)
    Draw-Line $ctx $d @(52, 33) @(66, 33)
  }

  'pillow' = {
    param($ctx, $ink, $accent)
    Draw-RoundRect $ctx (New-Pen $ctx $ink 6.2) 6 14 88 72 26
    # seam puff lines
    $p = New-Pen $ctx $accent 4.6
    Draw-Arc $ctx $p 26 27 48 24 35 110
    Draw-Arc $ctx $p 28 55 44 20 215 95
  }

  'mattress' = {
    param($ctx, $ink, $accent)
    Draw-RoundRect $ctx (New-Pen $ctx $ink 6.2) 4 16 92 68 16
    $p = New-Pen $ctx $accent 4.8
    Draw-Line $ctx $p @(16, 42) @(84, 42)
    Draw-Line $ctx $p @(16, 60) @(52, 60)
    $d = New-Pen $ctx $ink 3.4
    $d.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    Draw-Line $ctx $d @(60, 60) @(84, 60)
  }

  'cushion' = {
    param($ctx, $ink, $accent)
    Draw-RoundRect $ctx (New-Pen $ctx $ink 6.2) 8 12 84 76 22
    $p = New-Pen $ctx $accent 4.4
    $p.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    Draw-Line $ctx $p @(20, 50) @(80, 50)
  }

  'drape' = {
    param($ctx, $ink, $accent)
    # rod
    $p = New-Pen $ctx $ink 6.5
    Draw-Line $ctx $p @(8, 16) @(92, 16)
    # cloth tails
    $t = New-Pen $ctx $accent 4.6
    Draw-Polyline $ctx $t @(22, 22) @(22, 52) @(17, 66) @(19, 88)
    Draw-Polyline $ctx $t @(46, 22) @(46, 46) @(41, 62) @(43, 86)
    Draw-Polyline $ctx $t @(70, 22) @(70, 52) @(65, 66) @(67, 88)
  }

  'wall' = {
    param($ctx, $ink, $accent)
    $p = New-Pen $ctx $ink 6.5
    Draw-Line $ctx $p @(16, 92) @(16, 14)
    Draw-Line $ctx $p @(84, 92) @(84, 14)
    $w = New-Pen $ctx $accent 5.4
    Draw-Bezier $ctx $w @(16, 50, 38, 20, 62, 80, 84, 50)
  }

  'ceiling' = {
    param($ctx, $ink, $accent)
    $p = New-Pen $ctx $ink 6.4
    Draw-Line $ctx $p @(10, 18) @(90, 18)
    Draw-Line $ctx $p @(10, 18) @(10, 34)
    Draw-Line $ctx $p @(90, 18) @(90, 34)
    # cove smile
    $c = New-Pen $ctx $accent 5.6
    Draw-Arc $ctx $c 14 8 72 60 40 100
  }

  'pushpull' = {
    param($ctx, $ink, $accent)
    # surface curve
    $w = New-Pen $ctx $ink 5.6
    Draw-Bezier $ctx $w @(14, 58, 38, 30, 62, 30, 86, 58)
    # two arrows pressing down
    $a = New-Pen $ctx $accent 5.2
    Draw-Line $ctx $a @(34, 26) @(34, 54)
    Draw-Line $ctx $a @(66, 26) @(66, 54)
    Fill-Polygon $ctx (New-Object System.Drawing.SolidBrush($accent)) @(34, 62) @(28, 52) @(40, 52)
    Fill-Polygon $ctx (New-Object System.Drawing.SolidBrush($accent)) @(66, 62) @(60, 52) @(72, 52)
  }

  'opening' = {
    param($ctx, $ink, $accent)
    Draw-RoundRect $ctx (New-Pen $ctx $ink 6.2) 8 8 84 84 20
    Fill-Polygon $ctx (New-Object System.Drawing.SolidBrush($accent)) @(40, 40) @(60, 40) @(60, 60) @(40, 60)
  }

  'loft' = {
    param($ctx, $ink, $accent)
    $p = New-Pen $ctx $ink 6.0
    # bottom loop + top loop
    Draw-Ellipse $ctx $p 14 60 72 26
    $t = New-Pen $ctx $accent 5.0
    Draw-Ellipse $ctx $t 34 22 32 14
    # tangent guides
    $g2 = New-Pen $ctx $ink 4.2
    Draw-Line $ctx $g2 @(20, 72) @(36, 32)
    Draw-Line $ctx $g2 @(80, 72) @(64, 32)
  }

  'pipe' = {
    param($ctx, $ink, $accent)
    $p = New-Pen $ctx $ink 6.0
    # front ring
    Draw-Ellipse $ctx $p 12 32 34 36
    Draw-Ellipse $ctx (New-Pen $ctx $accent 3.8) 22 45 14 10
    # body sweeping right
    Draw-Line $ctx $p @(46, 32) @(78, 32)
    Draw-Line $ctx $p @(46, 68) @(78, 68)
    $s = New-Pen $ctx $ink 5.4
    Draw-Arc $ctx $s 60 32 34 36 270 180
  }
}

# ----------------------------------------------------------------------------
# Render loop
# ----------------------------------------------------------------------------
foreach ($name in $GLYPHS.Keys) {
  foreach ($size in @(24, 48)) {
    $ctx = New-Canvas $size

    # brushes passed for fill helpers
    $inkBrush = New-Object System.Drawing.SolidBrush($Ink)
    $accentBrush = New-Object System.Drawing.SolidBrush($Accent)
    $ctx | Add-Member -NotePropertyMembers @{ InkBrush = $inkBrush; AccentBrush = $accentBrush } -Force

    & $GLYPHS[$name] $ctx $Ink $Accent

    $file = if ($size -eq 24) { "icon_$name.png" } else { "icon_${name}@2x.png" }
    $path = Join-Path $OutDir $file
    $ctx.Bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $ctx.G.Dispose()
    $ctx.Bmp.Dispose()
    Write-Host ("  written  " + $path)
  }
}

# Product logo
foreach ($size in @(32, 256)) {
  $ctx = New-Canvas $size
  Draw-Logo $ctx
  $path = if ($size -eq 32) { (Join-Path $OutDir 'logo_32.png') } else { (Join-Path $Root 'icon.png') }
  $ctx.Bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $ctx.G.Dispose(); $ctx.Bmp.Dispose()
  Write-Host ("  written  " + $path)
}

# Vector twin of the product logo
$svg = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs>
    <linearGradient id="pg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#e25689"/>
      <stop offset="1" stop-color="#f2a25c"/>
    </linearGradient>
  </defs>
  <rect x="4" y="4" width="92" height="92" rx="26" fill="url(#pg)"/>
  <path d="M20 38c10-14 50-14 60 6M27 44c14-10 32 6 46 10" fill="none" stroke="#fffaf6" stroke-width="8" stroke-linecap="round"/>
</svg>
'@
Set-Content -Path (Join-Path $Root 'icon.svg') -Value $svg -Encoding UTF8
Write-Host ("  written  " + (Join-Path $Root 'icon.svg'))

Write-Host 'Plush icons complete.'
