Add-Type -AssemblyName System.Drawing

#  Параметры изображения 
$imgWidth  = 600
$imgHeight = 400
$marginLeft   = 60
$marginRight  = 30
$marginTop    = 40
$marginBottom = 50

$graphWidth  = $imgWidth - $marginLeft - $marginRight
$graphHeight = $imgHeight - $marginTop - $marginBottom

#  Физика 
$g_moon   = 1.625       # м/с² (лунное g)
$dryMass  = 4500.0      # кг
$fuelMass = 10500.0     # кг
$maxThrust = 45000.0    # Н
$totalMass = $dryMass + $fuelMass
$a_net = ($maxThrust / $totalMass) - $g_moon   # чистое замедляющее ускорение при полной тяге

# Диапазон осей
$vMax = 80.0   # м/с (скорость по модулю, ось X)
$hMax = 1800.0 # м (высота, ось Y)

#  Создаём bitmap 
$bmp = New-Object System.Drawing.Bitmap($imgWidth, $imgHeight)
$gr  = [System.Drawing.Graphics]::FromImage($bmp)
$gr.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$gr.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

#  Палитра (Matrix) 
$colorBg        = [System.Drawing.Color]::FromArgb(12, 14, 12)
$colorGrid      = [System.Drawing.Color]::FromArgb(25, 40, 25)
$colorAxis      = [System.Drawing.Color]::FromArgb(0, 180, 0)
$colorCurve     = [System.Drawing.Color]::FromArgb(0, 255, 70)
$colorTitle     = [System.Drawing.Color]::FromArgb(120, 255, 120)
$colorZone      = [System.Drawing.Color]::FromArgb(0, 140, 50)
$colorDanger    = [System.Drawing.Color]::FromArgb(0, 255, 0)
$colorAxisLabel = [System.Drawing.Color]::FromArgb(60, 160, 60)

#  Шрифты 
$fontTitle   = New-Object System.Drawing.Font("Fira Code", 18, [System.Drawing.FontStyle]::Bold)
$fontZone    = New-Object System.Drawing.Font("Fira Code", 14, [System.Drawing.FontStyle]::Bold)
$fontAxis    = New-Object System.Drawing.Font("Fira Code", 12)

#  Кисти и перья 
$brushBg        = New-Object System.Drawing.SolidBrush($colorBg)
$brushTitle     = New-Object System.Drawing.SolidBrush($colorTitle)
$brushZone      = New-Object System.Drawing.SolidBrush($colorZone)
$brushDanger    = New-Object System.Drawing.SolidBrush($colorDanger)
$brushAxisLabel = New-Object System.Drawing.SolidBrush($colorAxisLabel)

$penGrid   = New-Object System.Drawing.Pen($colorGrid, 1)
$penAxis   = New-Object System.Drawing.Pen($colorAxis, 2)
$penCurve  = New-Object System.Drawing.Pen($colorCurve, 3)

#  Фон 
$gr.FillRectangle($brushBg, 0, 0, $imgWidth, $imgHeight)

#  Вспомогательные функции для координат 
# V (скорость) -> пиксель X
function VtoX([double]$v) {
    return $marginLeft + ($v / $vMax) * $graphWidth
}
# H (высота) -> пиксель Y  (ось Y идёт вверх, пиксели — вниз)
function HtoY([double]$h) {
    return $marginTop + $graphHeight - ($h / $hMax) * $graphHeight
}

#  Сетка 
# вертикальные линии (по V)
for ($v = 0; $v -le $vMax; $v += 20) {
    $x = VtoX $v
    $gr.DrawLine($penGrid, $x, $marginTop, $x, ($marginTop + $graphHeight))
}
# горизонтальные линии (по H)
for ($h = 0; $h -le $hMax; $h += 400) {
    $y = HtoY $h
    $gr.DrawLine($penGrid, $marginLeft, $y, ($marginLeft + $graphWidth), $y)
}

#  Оси 
# ось X (нижняя граница)
$gr.DrawLine($penAxis, $marginLeft, ($marginTop + $graphHeight), ($marginLeft + $graphWidth), ($marginTop + $graphHeight))
# ось Y (левая граница)
$gr.DrawLine($penAxis, $marginLeft, $marginTop, $marginLeft, ($marginTop + $graphHeight))

#  Подписи осей 
$sfCenter = New-Object System.Drawing.StringFormat
$sfCenter.Alignment = [System.Drawing.StringAlignment]::Center

$gr.DrawString("вертикальная скорость", $fontAxis, $brushAxisLabel,
    ($marginLeft + $graphWidth / 2), ($imgHeight - 36), $sfCenter)

# подпись оси Y (вертикальная — рисуем с поворотом)
$state = $gr.Save()
$gr.TranslateTransform(22, ($marginTop + $graphHeight / 2))
$gr.RotateTransform(-90)
$gr.DrawString("высота", $fontAxis, $brushAxisLabel, 0, 0, $sfCenter)
$gr.Restore($state)

#  Кривая H = V² / (2 · a_net) 
$points = New-Object System.Collections.Generic.List[System.Drawing.PointF]
$step = 0.5
for ($v = 0; $v -le $vMax; $v += $step) {
    $h = ($v * $v) / (2.0 * $a_net)
    if ($h -gt $hMax) { break }
    $px = VtoX $v
    $py = HtoY $h
    $points.Add([System.Drawing.PointF]::new($px, $py))
}

if ($points.Count -ge 2) {
    $gr.DrawLines($penCurve, $points.ToArray())
}

#  Надписи зон
$sfZone = New-Object System.Drawing.StringFormat
$sfZone.Alignment = [System.Drawing.StringAlignment]::Center

# "свободное падение" — центр зоны выше кривой
$gr.DrawString("свободное падение", $fontZone, $brushZone,
    (VtoX 25), (HtoY 1200), $sfZone)

# "катастрофа" — центр зоны ниже кривой
$gr.DrawString("катастрофа", $fontZone, $brushDanger,
    (VtoX 60), (HtoY 450), $sfZone)

#  Заголовок 
$gr.DrawString("Момент включения полной тяги", $fontTitle, $brushTitle,
    ($marginLeft + 40), 8)

#  Сохранение 
$outputPath = Join-Path $PSScriptRoot "graph1.png"
try {
    $bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host ("Graph saved: " + $outputPath) -ForegroundColor Green
}
catch {
    Write-Host ("Error: " + $_.Exception.Message) -ForegroundColor Red
}
finally {
    $gr.Dispose()
    $bmp.Dispose()
}
