<#
  convert_maps.ps1 : mappy の地図 (GIF) を、AbysseanRadar が読める PNG にして maps/ に置く。

  使い方 (PowerShell):
    1. mappy の GitHub (KenshiDRK/mappy--Kenshi-Version) から、Maps フォルダーを手に入れる
       (リポジトリを ZIP でダウンロードして展開すれば、中に Maps フォルダーがあります)
    2. 次のように実行する
         powershell -ExecutionPolicy Bypass -File convert_maps.ps1 -Source "C:\...\mappy--Kenshi-Version-master\Maps"
       ゾーンを絞るとき (例: アビセア-ウルガラン = fd、グロウベルグ = fe):
         powershell -ExecutionPolicy Bypass -File convert_maps.ps1 -Source "C:\...\Maps" -Zones fd,fe

  やること:
    - Source の中の <ゾーン番号の16進数>_0.gif (と .png) を、8x8 の欠片 (64 x 64 枚 = 4096 枚) の PNG にして、AbysseanRadar\maps\<ゾーン>_0\ に置く (最初の地図だけ)
    - Source の map.ini を、AbysseanRadar\maps\map.ini にコピーする (座標の合わせ方が入っている)
  地図は mappy・ffassist の作者たちのもので、AbysseanRadar には同梱していません。自分の PC の中だけで使ってください。
  このスクリプトは、ゲームにも Windower にも触りません (ファイルを変換して置くだけ)。
#>
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [string[]]$Zones = @()
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Source のフォルダーが見つかりません: $Source" }
$ini = Join-Path $Source "map.ini"
if (-not (Test-Path -LiteralPath $ini)) { throw "Source に map.ini がありません。mappy の Maps フォルダーを指定してください: $Source" }

$dest = Join-Path (Split-Path -Parent $PSScriptRoot) "maps"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -LiteralPath $ini -Destination (Join-Path $dest "map.ini") -Force

# ゾーンを指定しないときは、アビセアの 10 ゾーン (1 ゾーンで欠片が 4096 枚になるので、全ゾーンは変換しない)
if ($Zones.Count -eq 0) { $Zones = @("0f", "2d", "84", "d7", "d8", "d9", "da", "fd", "fe", "ff") }
$want = @{}
foreach ($z in $Zones) { foreach ($part in ($z -split ",")) { if ($part.Trim()) { $want[$part.Trim().ToLower()] = $true } } }

$converted = 0
$tile = 8
foreach ($file in Get-ChildItem -LiteralPath $Source -File) {
    if ($file.Name -notmatch '^([0-9a-fA-F]{2,3})_0\.(gif|png)$') { continue }
    $zone = $Matches[1].ToLower()
    if ($want.Count -gt 0 -and -not $want.ContainsKey($zone)) { continue }
    $outDir = Join-Path $dest ("{0}_0" -f $zone)
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $img = [System.Drawing.Image]::FromFile($file.FullName)
    try {
        # 512x512 にそろえてから、8x8 の欠片 (64 x 64 枚) に切り分ける
        $full = New-Object System.Drawing.Bitmap 512, 512, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($full)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.DrawImage($img, 0, 0, 512, 512)
        } finally { $g.Dispose() }
        try {
            for ($row = 0; $row -lt 64; $row++) {
                for ($col = 0; $col -lt 64; $col++) {
                    $rect = New-Object System.Drawing.Rectangle ($col * $tile), ($row * $tile), $tile, $tile
                    $piece = $full.Clone($rect, $full.PixelFormat)
                    try { $piece.Save((Join-Path $outDir ("{0:D2}_{1:D2}.png" -f $row, $col)), [System.Drawing.Imaging.ImageFormat]::Png) } finally { $piece.Dispose() }
                }
            }
        } finally { $full.Dispose() }
    } finally { $img.Dispose() }
    $converted++
}
Write-Output ("変換した地図: {0} 枚 -> {1}" -f $converted, $dest)
if ($converted -eq 0) { Write-Output "地図が 1 枚も見つかりませんでした。-Zones の指定 (例: fd) と、Source のフォルダーを確かめてください。" }
