param([string]$outdir)
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $outdir | Out-Null

# --- 地図の縁 (マスク) map_mask_1〜6.png: 中心の半径 256 までは透明 (地図が見える)、その外に、幅 W の不透明な輪、さらに外は透明 ---
# 輪の幅は、拡大が大きいほど必要 (欠片のはみ出しを隠すため)。AbysseanRadar.lua の MAP_MASKS と同じ幅 (W / 256) にする
$widths = @(20, 32, 44, 60, 86, 128)
for ($i = 0; $i -lt $widths.Count; $i++) {
    $R = 256; $W = $widths[$i]; $C = $R + $W; $S = 2 * $C
    $bmp = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath ([System.Drawing.Drawing2D.FillMode]::Alternate)
    $path.AddEllipse($C - $R - $W, $C - $R - $W, 2 * ($R + $W), 2 * ($R + $W))
    $path.AddEllipse($C - $R, $C - $R, 2 * $R, 2 * $R)
    $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 30, 24, 15))), $path)
    # 内側の金の縁 (輪が細いときも見えるように太め) と、外側の細い縁
    $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 210, 175, 90)), 6), $C - $R, $C - $R, 2 * $R, 2 * $R)
    if ($W -ge 40) {
        $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 120, 95, 45)), 4), $C - $R - $W + 3, $C - $R - $W + 3, 2 * ($R + $W) - 6, 2 * ($R + $W) - 6)
    }
    $bmp.Save((Join-Path $outdir ("map_mask_{0}.png" -f ($i + 1))), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

# --- 地図の下に敷く暗い円盤 (256x256) ---
$bmp = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::Transparent)
$g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 20, 18, 14))), 0, 0, 255, 255)
$bmp.Save((Join-Path $outdir "map_disc.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# --- 欠片の最初の絵 (4x4 の小さな暗い画像。実際の欠片が入るまでのつなぎ) ---
$bmp = New-Object System.Drawing.Bitmap 4, 4, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(255, 20, 18, 14))
$bmp.Save((Join-Path $outdir "map_blank.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"ok"
