$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$appRoot = Split-Path $PSScriptRoot -Parent
$source = [System.Drawing.Image]::FromFile((Join-Path $appRoot 'branding/app_icon.png'))
function Write-IconPng([int]$size, [string]$path) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($source, 0, 0, $size, $size)
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
try {
    $densities = @{mdpi=48; hdpi=72; xhdpi=96; xxhdpi=144; xxxhdpi=192}
    foreach ($density in $densities.Keys) {
        Write-IconPng $densities[$density] (Join-Path $appRoot "android/app/src/main/res/mipmap-$density/ic_launcher.png")
    }
    # Windows ICO supports a PNG payload, preserving the supplied artwork.
    $tempPng = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    try {
        Write-IconPng 256 $tempPng
        $pngBytes = [System.IO.File]::ReadAllBytes($tempPng)
        $stream = [System.IO.File]::Create((Join-Path $appRoot 'windows/runner/resources/app_icon.ico'))
        $writer = [System.IO.BinaryWriter]::new($stream)
        try {
            $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)
            $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$pngBytes.Length); $writer.Write([uint32]22)
            $writer.Write($pngBytes)
        } finally { $writer.Dispose() }
    } finally { if (Test-Path -LiteralPath $tempPng) { Remove-Item -LiteralPath $tempPng } }
} finally { $source.Dispose() }
