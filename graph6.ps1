Add-Type -AssemblyName System.Drawing

# Читаем телеметрию из CSV файлов
$mode1aPath = Join-Path $PSScriptRoot "mode1a.log"
$mode2aPath = Join-Path $PSScriptRoot "mode2a.log"

function Read-Telemetry([string]$path, [double]$tMin) {
    $lines = [System.IO.File]::ReadAllLines($path)
    $result = [System.Collections.Generic.List[PSObject]]::new()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $parts = $lines[$i].Split(';')
        if ($parts.Count -lt 4) { continue }
        $t = [double]$parts[0]
        if ($t -lt $tMin) { continue }
        $result.Add([PSCustomObject]@{
            Time      = $t
            Height    = [double]$parts[1]
            ThrustPct = [double]$parts[3]
        })
    }
    return $result
}

$tMin = 60.0
$data1 = Read-Telemetry $mode1aPath $tMin
$data2 = Read-Telemetry $mode2aPath $tMin

# Определяем диапазоны осей
$tMinAxis = $tMin
$tMaxAxis = 0.0
$hMax = 0.0
foreach ($r in $data1) {
    if ($r.Time -gt $tMaxAxis) { $tMaxAxis = $r.Time }
    if ($r.Height -gt $hMax) { $hMax = $r.Height }
}
foreach ($r in $data2) {
    if ($r.Time -gt $tMaxAxis) { $tMaxAxis = $r.Time }
    if ($r.Height -gt $hMax) { $hMax = $r.Height }
}

# Округляем вверх для красивой сетки
$hMax = [Math]::Ceiling($hMax / 100) * 100
$tMaxAxis = [Math]::Ceiling($tMaxAxis / 10) * 10
$tRange = $tMaxAxis - $tMinAxis

# Параметры изображения
$pps = 4  # пикселей на секунду
$graphWidth = [int]($tRange * $pps)
$marginLeft = 60
$marginRight = 20
$marginBottom = 30
$gap = 40  # зазор между графиками

$graph1Height = 240  # высота
$graph2Height = 120  # тяга

$imgWidth = $graphWidth + $marginLeft + $marginRight
$imgHeight = 30 + $graph1Height + $gap + $graph2Height + $marginBottom

# Создаём bitmap
$bmp = New-Object System.Drawing.Bitmap($imgWidth, $imgHeight)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Фон
$g.Clear([System.Drawing.Color]::FromArgb(12, 14, 12))

# Шрифты и кисти
$fontNormal = New-Object System.Drawing.Font("Fira Code", 16)
$fontSmall = New-Object System.Drawing.Font("Fira Code", 10)
$fontLegend = New-Object System.Drawing.Font("Fira Code", 9)
$brushTitle = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 255, 120))
$brushAxis = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, 160, 60))
$brushMode1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 255, 70))
$brushMode2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(50, 255, 50))

# Перья
$penGrid = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(25, 40, 25), 1)
$penTick = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(35, 55, 35), 1)

$penMode1 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 100, 20), 2)
$penMode2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50, 255, 50), 2)

# Вспомогательные функции
function TtoX([double]$t) {
    return $marginLeft + (($t - $tMinAxis) / $tRange) * $graphWidth
}

function DrawTimeAxis($gfx, [double]$gx, [double]$gy, [double]$gw, [double]$gh) {
    # засечки каждую секунду
    for ($ts = [Math]::Ceiling($tMinAxis); $ts -le $tMaxAxis; $ts++) {
        $xPos = $gx + (($ts - $tMinAxis) / $tRange) * $gw
        $gfx.DrawLine($penTick, $xPos, $gy + $gh - 4, $xPos, $gy + $gh)
    }
    # сетка каждые 10 секунд
    for ($ts = [Math]::Ceiling($tMinAxis / 10) * 10; $ts -le $tMaxAxis; $ts += 10) {
        $xPos = $gx + (($ts - $tMinAxis) / $tRange) * $gw
        $gfx.DrawLine($penTick, $xPos, $gy, $xPos, $gy + $gh)
        $gfx.DrawString("{0:F0}с" -f $ts, $fontSmall, $brushAxis, $xPos - 12, $gy + $gh + 4)
    }
}

# График 1: ВЫСОТА

$g1X = $marginLeft
$g1Y = 30

$g.DrawRectangle($penGrid, $g1X, $g1Y, $graphWidth, $graph1Height)
$g.DrawString("ВЫСОТА, м", $fontNormal, $brushTitle, $g1X, $g1Y - 24)

# сетка по высоте
$hStep = 100
if ($hMax -gt 500) { $hStep = 200 }
if ($hMax -gt 1000) { $hStep = 500 }
for ($h = 0; $h -le $hMax; $h += $hStep) {
    $yPos = $g1Y + $graph1Height - ($h / $hMax) * $graph1Height
    $g.DrawLine($penGrid, $g1X, $yPos, $g1X + $graphWidth, $yPos)
    $g.DrawString("{0:F0}" -f $h, $fontSmall, $brushAxis, $g1X - 50, $yPos - 9)
}

# ось времени
DrawTimeAxis $g $g1X $g1Y $graphWidth $graph1Height

# mode1a
for ($i = 0; $i -lt ($data1.Count - 1); $i++) {
    $x1 = TtoX $data1[$i].Time
    $x2 = TtoX $data1[$i + 1].Time
    $y1 = $g1Y + $graph1Height - ($data1[$i].Height / $hMax) * $graph1Height
    $y2 = $g1Y + $graph1Height - ($data1[$i + 1].Height / $hMax) * $graph1Height
    $g.DrawLine($penMode1, $x1, $y1, $x2, $y2)
}

# mode2a
for ($i = 0; $i -lt ($data2.Count - 1); $i++) {
    $x1 = TtoX $data2[$i].Time
    $x2 = TtoX $data2[$i + 1].Time
    $y1 = $g1Y + $graph1Height - ($data2[$i].Height / $hMax) * $graph1Height
    $y2 = $g1Y + $graph1Height - ($data2[$i + 1].Height / $hMax) * $graph1Height
    $g.DrawLine($penMode2, $x1, $y1, $x2, $y2)
}

# График 2: ТЯГА

$g2X = $marginLeft
$g2Y = $g1Y + $graph1Height + $gap
$thrustMax = 100.0

$g.DrawRectangle($penGrid, $g2X, $g2Y, $graphWidth, $graph2Height)
$g.DrawString("ТЯГА, %", $fontNormal, $brushTitle, $g2X, $g2Y - 24)

# сетка по тяге (каждые 20%)
for ($tp = 0; $tp -le 100; $tp += 20) {
    $yPos = $g2Y + $graph2Height - ($tp / $thrustMax) * $graph2Height
    $g.DrawLine($penGrid, $g2X, $yPos, $g2X + $graphWidth, $yPos)
    $g.DrawString("{0:F0}%" -f $tp, $fontSmall, $brushAxis, $g2X - 50, $yPos - 9)
}

# ось времени
DrawTimeAxis $g $g2X $g2Y $graphWidth $graph2Height

# mode1a
for ($i = 0; $i -lt ($data1.Count - 1); $i++) {
    $x1 = TtoX $data1[$i].Time
    $x2 = TtoX $data1[$i + 1].Time
    $y1 = $g2Y + $graph2Height - ($data1[$i].ThrustPct / $thrustMax) * $graph2Height
    $y2 = $g2Y + $graph2Height - ($data1[$i + 1].ThrustPct / $thrustMax) * $graph2Height
    $g.DrawLine($penMode1, $x1, $y1, $x2, $y2)
}

# mode2a
for ($i = 0; $i -lt ($data2.Count - 1); $i++) {
    $x1 = TtoX $data2[$i].Time
    $x2 = TtoX $data2[$i + 1].Time
    $y1 = $g2Y + $graph2Height - ($data2[$i].ThrustPct / $thrustMax) * $graph2Height
    $y2 = $g2Y + $graph2Height - ($data2[$i + 1].ThrustPct / $thrustMax) * $graph2Height
    $g.DrawLine($penMode2, $x1, $y1, $x2, $y2)
}

# Легенда

$legendX = $g1X + $graphWidth - 200
$legendY = $g1Y + 10
$g.DrawLine($penMode1, $legendX, ($legendY + 6), ($legendX + 25), ($legendY + 6))
$g.DrawString("mode1a (классика)", $fontLegend, $brushMode1, ($legendX + 30), $legendY)
$g.DrawLine($penMode2, $legendX, ($legendY + 20), ($legendX + 25), ($legendY + 20))
$g.DrawString("mode2a (G-FOLD)", $fontLegend, $brushMode2, ($legendX + 30), ($legendY + 14))

# Сохранение

$outputPath = Join-Path $PSScriptRoot "graph6.png"
try {
    $bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host ("График сохранён: " + $outputPath) -ForegroundColor Green
}
catch {
    Write-Host ("Ошибка сохранения: " + $_.Exception.Message) -ForegroundColor Red
}
finally {
    $g.Dispose()
    $bmp.Dispose()
}
