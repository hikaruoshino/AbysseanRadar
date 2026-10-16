param([string]$outdir)
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $outdir | Out-Null

function New-Canvas($w, $h) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    return @($bmp, $g)
}
function Save($bmp, $g, $name) {
    $bmp.Save((Join-Path $outdir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

# --- レーダーの背景 (256x256。円盤・距離の輪・十字・縁。北の印は別の画像 north.png) ---
$c = New-Canvas 256 256; $bmp = $c[0]; $g = $c[1]
$g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150, 8, 14, 30))), 2, 2, 252, 252)
$ringPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(110, 120, 170, 255)), 1
foreach ($r in @(42, 84)) { $g.DrawEllipse($ringPen, 128 - $r, 128 - $r, 2 * $r, 2 * $r) }
$g.DrawLine($ringPen, 128, 6, 128, 250); $g.DrawLine($ringPen, 6, 128, 250, 128)
$edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(230, 210, 175, 90)), 3
$g.DrawEllipse($edge, 2, 2, 252, 252)
Save $bmp $g "radar_bg.png"

# --- 北の印 (金色の三角。回して置けないので、向きに合わせて縁の上を動かす) ---
$c = New-Canvas 20 20; $bmp = $c[0]; $g = $c[1]
$g.FillPolygon((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 255, 215, 100))), @(
    (New-Object System.Drawing.Point 10, 1), (New-Object System.Drawing.Point 2, 17), (New-Object System.Drawing.Point 18, 17)))
$g.DrawPolygon((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 40, 30, 10)), 1), @(
    (New-Object System.Drawing.Point 10, 1), (New-Object System.Drawing.Point 2, 17), (New-Object System.Drawing.Point 18, 17)))
Save $bmp $g "north.png"

# --- 星 (アビセアン・NM の印。赤い ★ に白い縁) ---
function Get-StarPoints($cx, $cy, $outer, $inner) {
    $pts = @()
    for ($i = 0; $i -lt 10; $i++) {
        $rad = if ($i % 2 -eq 0) { $outer } else { $inner }
        $ang = [Math]::PI * $i / 5 - [Math]::PI / 2
        $pts += (New-Object System.Drawing.PointF ([float]($cx + $rad * [Math]::Cos($ang))), ([float]($cy + $rad * [Math]::Sin($ang))))
    }
    return $pts
}
$c = New-Canvas 32 32; $bmp = $c[0]; $g = $c[1]
$pts = Get-StarPoints 16 17 14 6
$g.FillPolygon((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 235, 40, 40))), $pts)
$g.DrawPolygon((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 255, 255)), 2), $pts)
Save $bmp $g "star.png"

# --- ダイヤ (PH の印。青い ◆ に白い縁) ---
$c = New-Canvas 28 28; $bmp = $c[0]; $g = $c[1]
$dia = @((New-Object System.Drawing.Point 14, 2), (New-Object System.Drawing.Point 25, 14), (New-Object System.Drawing.Point 14, 26), (New-Object System.Drawing.Point 3, 14))
$g.FillPolygon((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 50, 120, 245))), $dia)
$g.DrawPolygon((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 255, 255)), 2), $dia)
Save $bmp $g "diamond.png"

# --- 小さな点 (各回の見込み = 黄、自分 = 緑) ---
function Save-Dot($name, $size, $r, $gr, $b) {
    $c = New-Canvas $size $size; $bmp = $c[0]; $g = $c[1]
    $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, $r, $gr, $b))), 1, 1, $size - 2, $size - 2)
    $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 255, 255)), 1), 1, 1, $size - 3, $size - 3)
    Save $bmp $g $name
}
Save-Dot "dot_hist.png" 10 240 210 80
Save-Dot "dot_me.png" 12 80 220 120

# --- 確からしさの輪 ---
$c = New-Canvas 128 128; $bmp = $c[0]; $g = $c[1]
$g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220, 255, 120, 120)), 3), 3, 3, 122, 122)
Save $bmp $g "ring.png"

# --- 矢印 (白。16 方向。0 = 上、時計回り。色は表示のときに付ける) ---
for ($k = 0; $k -lt 16; $k++) {
    $c = New-Canvas 26 26; $bmp = $c[0]; $g = $c[1]
    $g.TranslateTransform(13, 13)
    $g.RotateTransform([float]($k * 22.5))
    $arrow = @((New-Object System.Drawing.Point 0, -11), (New-Object System.Drawing.Point 7, 3), (New-Object System.Drawing.Point 2, 1),
               (New-Object System.Drawing.Point 2, 11), (New-Object System.Drawing.Point -2, 11), (New-Object System.Drawing.Point -2, 1), (New-Object System.Drawing.Point -7, 3))
    $g.FillPolygon((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255, 255))), $arrow)
    $g.DrawPolygon((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 20, 20, 20)), 1), $arrow)
    Save $bmp $g ("arrow_{0:D2}.png" -f $k)
}
"ok"

# --- 色を付けて使う白い星と輪 (段階ごとに色を変える) ---
$c = New-Canvas 32 32; $bmp = $c[0]; $g = $c[1]
$pts = Get-StarPoints 16 17 14 6
$g.FillPolygon((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255, 255))), $pts)
$g.DrawPolygon((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 30, 30, 30)), 2), $pts)
Save $bmp $g "star_white.png"
$c = New-Canvas 128 128; $bmp = $c[0]; $g = $c[1]
$g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(230, 255, 255, 255)), 3), 3, 3, 122, 122)
Save $bmp $g "ring_white.png"
"ok2"
