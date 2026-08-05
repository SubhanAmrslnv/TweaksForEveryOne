<#
.SYNOPSIS
    Regenerates assets\WindowTweaks.ico.

.DESCRIPTION
    Draws the icon with System.Drawing at each size, then assembles the ICO
    container by hand.

    Why by hand: Bitmap.GetHicon() / Icon.Save() can only ever write a
    single-image .ico. A real icon needs one image per size, or Windows scales
    the wrong one and the 16px taskbar version turns to mush. The container is
    just a 6-byte ICONDIR followed by one 16-byte ICONDIRENTRY per image, so
    building it is easier than taking on a dependency.

    Sizes 16-64 are stored as 32-bit BGRA DIBs (the universally understood
    form); 256 is stored as a PNG, which every Vista-and-later tool expects and
    which keeps the file small.

    The .ico is committed, so this only needs running when the artwork changes.

.NOTES
    Two naming traps cost real time when this was written, both the PowerShell
    equivalent of the `oR` / `or` collision the AutoHotkey source documents:

    - Do not name a helper here with a single letter. PowerShell resolves
      aliases before functions, so a function called `R` is shadowed by the
      built-in `r` alias for Invoke-History.
    - Do not rely on a script-scope variable being visible inside a function
      when any caller in between might have a same-named local. Variables are
      case-insensitive and lookup is dynamic, so a local `$bar` (a height)
      silently shadows a script-scope `$BAR` (a colour) - and
      `SolidBrush(16.0)` does not throw, it quietly yields
      Color [A=0,R=0,G=0,B=16], i.e. fully transparent. The drawing simply
      vanishes with no error. Every colour below is passed as a parameter.
#>
[CmdletBinding()]
param(
    [string]$OutFile = (Join-Path $PSScriptRoot 'WindowTweaks.ico')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$SIZES    = 16, 32, 48, 64, 256
$PNG_FROM = 256      # this size and up are stored as PNG, below it as a DIB

# Two overlapping windows, the front one separated from the back one by a
# punched-out gap rather than an outline - a gap reads correctly on a light or
# a dark taskbar, where a fixed-colour outline only works on one of them.
# Flat and two-tone so it survives 16px, where any gradient turns to grey mud.
$COL_BACK  = [System.Drawing.Color]::FromArgb(255, 118, 136, 158)   # muted slate
$COL_FRONT = [System.Drawing.Color]::FromArgb(255,  56, 139, 232)   # accent blue
$COL_TITLE = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)   # title bars

function New-UnitRect($unit, $x, $y, $w, $h) {
    New-Object System.Drawing.RectangleF(
        [single]($x * $unit), [single]($y * $unit),
        [single]($w * $unit), [single]($h * $unit))
}

function New-RoundedPath($rect, $radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    # Below ~1.5px the corner radius can't be resolved; a plain rectangle is
    # sharper than a rounded one that only muddies the corner pixels.
    if ($radius -lt 1.5) {
        $path.AddRectangle($rect)
    } else {
        $d = $radius * 2
        $path.AddArc($rect.X,           $rect.Y,           $d, $d, 180, 90)
        $path.AddArc($rect.Right  - $d, $rect.Y,           $d, $d, 270, 90)
        $path.AddArc($rect.Right  - $d, $rect.Bottom - $d, $d, $d,   0, 90)
        $path.AddArc($rect.X,           $rect.Bottom - $d, $d, $d,  90, 90)
        $path.CloseFigure()
    }
    return $path
}

function Add-Window($graphics, $rect, $bodyColour, $titleColour, $radius, $barHeight) {
    $path = New-RoundedPath $rect $radius
    try {
        $brush = New-Object System.Drawing.SolidBrush($bodyColour)
        $graphics.FillPath($brush, $path)
        $brush.Dispose()

        # Title bar: a strip across the top clipped to the same shape, so it
        # inherits the rounded corners instead of poking out of them.
        if ($barHeight -ge 1.0) {
            $saved = $graphics.Clip
            $graphics.SetClip($path)
            $barBrush = New-Object System.Drawing.SolidBrush($titleColour)
            $graphics.FillRectangle($barBrush, $rect.X, $rect.Y, $rect.Width, [single]$barHeight)
            $barBrush.Dispose()
            $graphics.Clip = $saved
        }
    } finally {
        $path.Dispose()
    }
}

function Clear-Gap($graphics, $rect, $radius) {
    # Erase to fully transparent instead of painting an outline. SourceCopy
    # replaces the destination pixels rather than blending, which is the only
    # way to punch a real hole in an ARGB bitmap.
    $path = New-RoundedPath $rect $radius
    try {
        $saved = $graphics.CompositingMode
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Transparent)
        $graphics.FillPath($brush, $path)
        $brush.Dispose()
        $graphics.CompositingMode = $saved
    } finally {
        $path.Dispose()
    }
}

function New-Frame([int]$px, $backColour, $frontColour, $titleColour) {
    $bmp = New-Object System.Drawing.Bitmap($px, $px,
                     [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)

        # Geometry is expressed on a 32-unit grid and scaled, so every size is
        # drawn at its own resolution rather than downsampled from one bitmap.
        $unit   = $px / 32.0
        $radius = [single]([Math]::Max(1.0, 2.75 * $unit))
        $gap    = [Math]::Max(1.0, 1.0 * $unit)

        # At 16px a proportional title bar rounds to a single white row that
        # just fuzzes the shape, so below 32px the bar is dropped and the two
        # windows are told apart by colour and the punched gap alone.
        $barPx = if ($px -lt 32) { 0.0 } else { [single](2.25 * $unit) }

        # Pushed out to the corners: at 16px the whole glyph is 16 pixels wide,
        # so every unit of margin is a pixel of legibility given away.
        $backRect  = New-UnitRect $unit  1.5  3.5 18 13
        $frontRect = New-UnitRect $unit 12.5 15.5 18 13

        # Back window, then a punched gap the size of the front window plus a
        # margin, then the front window sitting inside that gap.
        Add-Window $graphics $backRect $backColour $titleColour $radius $barPx

        $gapRect = New-Object System.Drawing.RectangleF(
            [single]($frontRect.X - $gap), [single]($frontRect.Y - $gap),
            [single]($frontRect.Width + $gap * 2), [single]($frontRect.Height + $gap * 2))
        Clear-Gap $graphics $gapRect ([single]($radius + $gap))

        Add-Window $graphics $frontRect $frontColour $titleColour $radius $barPx
    } finally {
        $graphics.Dispose()
    }
    return $bmp
}

function ConvertTo-IcoDib($bmp, [int]$px) {
    # A DIB inside an .ico is a BITMAPINFOHEADER with doubled height (colour
    # rows plus an AND mask that follows), bottom-up BGRA rows, and no
    # BITMAPFILEHEADER. The mask is required even for 32-bit images: some shell
    # paths still read it, and an absent one renders black.
    $stride     = $px * 4
    $maskStride = [int]([Math]::Floor(($px + 31) / 32)) * 4

    $header = New-Object byte[] 40
    [BitConverter]::GetBytes([int]40).CopyTo($header, 0)            # biSize
    [BitConverter]::GetBytes([int]$px).CopyTo($header, 4)           # biWidth
    [BitConverter]::GetBytes([int]($px * 2)).CopyTo($header, 8)     # biHeight (xor+and)
    [BitConverter]::GetBytes([int16]1).CopyTo($header, 12)          # biPlanes
    [BitConverter]::GetBytes([int16]32).CopyTo($header, 14)         # biBitCount
    [BitConverter]::GetBytes([int]0).CopyTo($header, 16)            # BI_RGB
    [BitConverter]::GetBytes([int]($stride * $px + $maskStride * $px)).CopyTo($header, 20)

    $area = New-Object System.Drawing.Rectangle(0, 0, $px, $px)
    $bits = $bmp.LockBits($area,
                [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $pixels = New-Object byte[] ($stride * $px)
    try {
        # Row by row, bottom-up: DIB scanlines run the opposite way to GDI+ ones.
        for ($y = 0; $y -lt $px; $y++) {
            $src = [IntPtr]::Add($bits.Scan0, $bits.Stride * ($px - 1 - $y))
            [System.Runtime.InteropServices.Marshal]::Copy($src, $pixels, $y * $stride, $stride)
        }
    } finally {
        $bmp.UnlockBits($bits)
    }

    # AND mask left all-zero: with a real alpha channel present, fully opaque is
    # correct and the alpha does the actual shaping.
    $mask = New-Object byte[] ($maskStride * $px)

    $out = New-Object byte[] ($header.Length + $pixels.Length + $mask.Length)
    $header.CopyTo($out, 0)
    $pixels.CopyTo($out, $header.Length)
    $mask.CopyTo($out, $header.Length + $pixels.Length)
    return ,$out
}

function ConvertTo-IcoPng($bmp) {
    $ms = New-Object System.IO.MemoryStream
    try {
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        return ,$ms.ToArray()
    } finally {
        $ms.Dispose()
    }
}

# ---- build each image, then the container ------------------------------------
# Payloads first: every directory entry needs its image's length and offset.
$images = @()
foreach ($px in $SIZES) {
    $bmp = New-Frame $px $COL_BACK $COL_FRONT $COL_TITLE
    try {
        $bytes = if ($px -ge $PNG_FROM) { ConvertTo-IcoPng $bmp } else { ConvertTo-IcoDib $bmp $px }
        $images += [pscustomobject]@{ Size = $px; Bytes = $bytes }
    } finally {
        $bmp.Dispose()
    }
}

$stream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($stream)
try {
    $writer.Write([int16]0)                 # reserved
    $writer.Write([int16]1)                 # 1 = icon
    $writer.Write([int16]$images.Count)

    $offset = 6 + (16 * $images.Count)      # ICONDIR + one entry per image
    foreach ($img in $images) {
        # 256 is stored as a literal 0 in the single width/height byte.
        $dim = if ($img.Size -ge 256) { [byte]0 } else { [byte]$img.Size }
        $writer.Write($dim)                 # width
        $writer.Write($dim)                 # height
        $writer.Write([byte]0)              # palette entries (0 = truecolour)
        $writer.Write([byte]0)              # reserved
        $writer.Write([int16]1)             # colour planes
        $writer.Write([int16]32)            # bits per pixel
        $writer.Write([int]$img.Bytes.Length)
        $writer.Write([int]$offset)
        $offset += $img.Bytes.Length
    }
    foreach ($img in $images) { $writer.Write($img.Bytes) }
    $writer.Flush()

    [System.IO.File]::WriteAllBytes($OutFile, $stream.ToArray())
} finally {
    $writer.Dispose()
    $stream.Dispose()
}

$kb = [math]::Round((Get-Item $OutFile).Length / 1KB, 1)
Write-Host "  Wrote $OutFile  ($kb KB, sizes $($SIZES -join ', '))" -ForegroundColor Green
