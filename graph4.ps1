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
$g_moon   = 1.625       # м/с²
$dryMass  = 4500.0      # кг
$fuelMass = 10500.0     # кг
$maxThrust = 45000.0    # Н
$totalMass = $dryMass + $fuelMass
$a_net = ($maxThrust / $totalMass) - $g_moon

# Комфортная посадка: тяга чуть меньше зависания
$hoverThrust = $totalMass * $g_moon
$driftFraction = 0.85   # 85% от зависания — плавный дрейф вниз
$driftThrust = $hoverThrust * $driftFraction
$a_drift = $g_moon - ($driftThrust / $totalMass)  # маленькое ускорение вниз

# Диапазон осей
$vMax = 80.0   # м/с
$hMax = 1800.0 # м

#  Создаём bitmap
$bmp = New-Object System.Drawing.Bitmap($imgWidth, $imgHeight)
$gr  = [System.Drawing.Graphics]::FromImage($bmp)
$gr.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$gr.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

#  Палитра (Matrix)
$colorBg         = [System.Drawing.Color]::FromArgb(12, 14, 12)
$colorGrid       = [System.Drawing.Color]::FromArgb(25, 40, 25)
$colorAxis       = [System.Drawing.Color]::FromArgb(0, 180, 0)
$colorCurve      = [System.Drawing.Color]::FromArgb(0, 255, 70)
$colorTitle      = [System.Drawing.Color]::FromArgb(120, 255, 120)
$colorAxisLabel  = [System.Drawing.Color]::FromArgb(60, 160, 60)
$colorTrajectory = [System.Drawing.Color]::FromArgb(50, 255, 50)

#  Шрифты
$fontTitle   = New-Object System.Drawing.Font("Fira Code", 18, [System.Drawing.FontStyle]::Bold)
$fontAxis    = New-Object System.Drawing.Font("Fira Code", 12)
$fontLegend  = New-Object System.Drawing.Font("Fira Code", 9)

#  Кисти и перья
$brushBg         = New-Object System.Drawing.SolidBrush($colorBg)
$brushTitle      = New-Object System.Drawing.SolidBrush($colorTitle)
$brushAxisLabel  = New-Object System.Drawing.SolidBrush($colorAxisLabel)
$brushCurve      = New-Object System.Drawing.SolidBrush($colorCurve)
$brushTrajectory = New-Object System.Drawing.SolidBrush($colorTrajectory)

$penGrid   = New-Object System.Drawing.Pen($colorGrid, 1)
$penAxis   = New-Object System.Drawing.Pen($colorAxis, 2)
$penCurve  = New-Object System.Drawing.Pen($colorCurve, 3)
$penTraj   = New-Object System.Drawing.Pen($colorTrajectory, 3)
$penTraj.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash

#  Фон
$gr.FillRectangle($brushBg, 0, 0, $imgWidth, $imgHeight)

#  Вспомогательные функции для координат
function VtoX([double]$v) {
    return $marginLeft + ($v / $vMax) * $graphWidth
}
function HtoY([double]$h) {
    return $marginTop + $graphHeight - ($h / $hMax) * $graphHeight
}

#  Сетка
for ($v = 0; $v -le $vMax; $v += 20) {
    $x = VtoX $v
    $gr.DrawLine($penGrid, $x, $marginTop, $x, ($marginTop + $graphHeight))
}
for ($h = 0; $h -le $hMax; $h += 400) {
    $y = HtoY $h
    $gr.DrawLine($penGrid, $marginLeft, $y, ($marginLeft + $graphWidth), $y)
}

#  Оси
$gr.DrawLine($penAxis, $marginLeft, ($marginTop + $graphHeight), ($marginLeft + $graphWidth), ($marginTop + $graphHeight))
$gr.DrawLine($penAxis, $marginLeft, $marginTop, $marginLeft, ($marginTop + $graphHeight))

#  Подписи осей
$sfCenter = New-Object System.Drawing.StringFormat
$sfCenter.Alignment = [System.Drawing.StringAlignment]::Center

$gr.DrawString("вертикальная скорость", $fontAxis, $brushAxisLabel,
    ($marginLeft + $graphWidth / 2), ($imgHeight - 36), $sfCenter)

$state = $gr.Save()
$gr.TranslateTransform(22, ($marginTop + $graphHeight / 2))
$gr.RotateTransform(-90)
$gr.DrawString("высота", $fontAxis, $brushAxisLabel, 0, 0, $sfCenter)
$gr.Restore($state)

#  Кривая идеальная H = V² / (2 · a_net) — граница торможения
$step = 0.5
$points = New-Object System.Collections.Generic.List[System.Drawing.PointF]
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

#  Моделирование комфортной траектории
# Фаза 0: управляемый дрейф — тяга 85% от зависания, плавный набор скорости
# Фаза 1: линейное торможение — V пропорциональна H, прямая линия к (0,0)
#          V = k*H, где k = V_peak / H_peak в момент перехода
#          Требуемое замедление = k*V, тяга = m*(k*V + g)
#          При V->0 тяга плавно переходит в зависание

$dt = 0.05
$simV = 0.0
$simH = $hMax
$simPhase = 0
$k = 0.0

$trajPoints = New-Object System.Collections.Generic.List[System.Drawing.PointF]
$trajPoints.Add([System.Drawing.PointF]::new((VtoX $simV), (HtoY $simH)))

$maxIter = 100000
$iter = 0
while ($simH -gt 0 -and $simV -ge 0 -and $iter -lt $maxIter) {
    $iter++
    if ($simPhase -eq 0) {
        # управляемый дрейф вниз
        $simV += $a_drift * $dt
        $simH -= $simV * $dt

        # переход на линейное торможение на половине высоты
        if ($simH -le $hMax * 0.5) {
            $simPhase = 1
            $k = $simV / $simH
        }
    }
    else {
        # линейное торможение: V = k*H -> замедление = k*V
        $aDecel = $k * $simV
        $thrust = $totalMass * ($aDecel + $g_moon)
        $thrust = [Math]::Min($thrust, $maxThrust)
        $accel = ($thrust / $totalMass) - $g_moon
        $simV -= $accel * $dt
        if ($simV -lt 0) { $simV = 0 }
        $simH -= $simV * $dt
        if ($simV -le 0.1 -or $simH -le 1.0) { break }
    }
    if ($simH -lt 0) { $simH = 0 }
    $trajPoints.Add([System.Drawing.PointF]::new((VtoX $simV), (HtoY $simH)))
}

$trajPoints.Add([System.Drawing.PointF]::new((VtoX 0), (HtoY 0)))

if ($trajPoints.Count -ge 2) {
    $gr.DrawLines($penTraj, $trajPoints.ToArray())
}

#  Легенда
$legendX = $marginLeft + 15
$legendY = $marginTop + 10
$gr.DrawLine($penCurve, $legendX, ($legendY + 6), ($legendX + 25), ($legendY + 6))
$gr.DrawString("момент полной тяги", $fontLegend, $brushCurve, ($legendX + 30), $legendY)
$gr.DrawLine($penTraj, $legendX, ($legendY + 22), ($legendX + 25), ($legendY + 22))
$gr.DrawString("комфортная посадка", $fontLegend, $brushTrajectory, ($legendX + 30), ($legendY + 16))

#  Заголовок
$gr.DrawString("Комфортная посадка", $fontTitle, $brushTitle,
    ($marginLeft + 100), 8)

#  Сохранение
$outputPath = Join-Path $PSScriptRoot "graph4.png"
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
