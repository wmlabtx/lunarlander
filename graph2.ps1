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
$t_delay = 2.0          # задержка выхода на полную тягу (с): зажигание + выход на режим

# Диапазон осей
$vMax = 80.0   # м/с (скорость по модулю, ось X)
$hMax = 1800.0 # м (высота, ось Y)

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
$colorCurveDelay = [System.Drawing.Color]::FromArgb(0, 100, 30)
$colorTitle      = [System.Drawing.Color]::FromArgb(120, 255, 120)
$colorZone       = [System.Drawing.Color]::FromArgb(0, 140, 50)
$colorDanger     = [System.Drawing.Color]::FromArgb(0, 255, 0)
$colorAxisLabel  = [System.Drawing.Color]::FromArgb(60, 160, 60)

#  Шрифты
$fontTitle   = New-Object System.Drawing.Font("Fira Code", 18, [System.Drawing.FontStyle]::Bold)
$fontZone    = New-Object System.Drawing.Font("Fira Code", 14, [System.Drawing.FontStyle]::Bold)
$fontAxis    = New-Object System.Drawing.Font("Fira Code", 12)
$fontLegend  = New-Object System.Drawing.Font("Fira Code", 9)

#  Кисти и перья
$brushBg         = New-Object System.Drawing.SolidBrush($colorBg)
$brushTitle      = New-Object System.Drawing.SolidBrush($colorTitle)
$brushZone       = New-Object System.Drawing.SolidBrush($colorZone)
$brushDanger     = New-Object System.Drawing.SolidBrush($colorDanger)
$brushAxisLabel  = New-Object System.Drawing.SolidBrush($colorAxisLabel)
$brushCurve      = New-Object System.Drawing.SolidBrush($colorCurve)
$brushCurveDelay = New-Object System.Drawing.SolidBrush($colorCurveDelay)

$colorTrajectory = [System.Drawing.Color]::FromArgb(50, 255, 50)
$brushTrajectory = New-Object System.Drawing.SolidBrush($colorTrajectory)

$penGrid       = New-Object System.Drawing.Pen($colorGrid, 1)
$penAxis       = New-Object System.Drawing.Pen($colorAxis, 2)
$penCurve      = New-Object System.Drawing.Pen($colorCurve, 3)
$penCurveDelay = New-Object System.Drawing.Pen($colorCurveDelay, 2)
$penTraj       = New-Object System.Drawing.Pen($colorTrajectory, 3)
$penTraj.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash

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

#  Кривая с задержкой (рисуем первой — она будет под основной)
# За время t_delay скорость вырастет на g*t_delay,
# высота уменьшится на V*t_delay + 0.5*g*t_delay²
# H = (V + g*t_delay)² / (2*a_net) + V*t_delay + 0.5*g*t_delay²
$step = 0.5
$pointsDelay = New-Object System.Collections.Generic.List[System.Drawing.PointF]
for ($v = 0; $v -le $vMax; $v += $step) {
    $vAfter = $v + $g_moon * $t_delay
    $hBrake = ($vAfter * $vAfter) / (2.0 * $a_net)
    $hFall  = $v * $t_delay + 0.5 * $g_moon * $t_delay * $t_delay
    $h = $hBrake + $hFall
    if ($h -gt $hMax) { break }
    $px = VtoX $v
    $py = HtoY $h
    $pointsDelay.Add([System.Drawing.PointF]::new($px, $py))
}

if ($pointsDelay.Count -ge 2) {
    $gr.DrawLines($penCurveDelay, $pointsDelay.ToArray())
}

#  Кривая идеальная H = V² / (2 · a_net)
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

#  Моделирование траектории посадки
$dt = 0.05
$simV = 0.0       # скорость (положительная = вниз)
$simH = $hMax     # высота старта
$simPhase = 0     # 0=свободное падение, 1=разгон двигателя, 2=адаптивная тяга
$rampTime = 0.0   # время внутри фазы разгона

$trajPoints = New-Object System.Collections.Generic.List[System.Drawing.PointF]
$trajPoints.Add([System.Drawing.PointF]::new((VtoX $simV), (HtoY $simH)))

while ($simH -gt 0 -and $simV -ge 0 -and $simV -lt $vMax) {
    if ($simPhase -eq 0) {
        # свободное падение — проверяем касание кривой с задержкой
        $vAfter = $simV + $g_moon * $t_delay
        $hBrake = ($vAfter * $vAfter) / (2.0 * $a_net)
        $hFall  = $simV * $t_delay + 0.5 * $g_moon * $t_delay * $t_delay
        $hDelayNeeded = $hBrake + $hFall
        if ($simH -le $hDelayNeeded) {
            $simPhase = 1
            $rampTime = 0.0
        }
        $simV += $g_moon * $dt
        $simH -= $simV * $dt
    }
    elseif ($simPhase -eq 1) {
        # двигатель разгоняется: тяга линейно от 0 до maxThrust за t_delay
        $rampTime += $dt
        $thrustFrac = [Math]::Min($rampTime / $t_delay, 1.0)
        $thrust = $maxThrust * $thrustFrac
        $accel = ($thrust / $totalMass) - $g_moon
        $simV -= $accel * $dt
        if ($simV -lt 0) { $simV = 0 }
        $simH -= $simV * $dt
        if ($rampTime -ge $t_delay) {
            $simPhase = 2
        }
    }
    else {
        # адаптивная тяга: a_required = V²/(2H), чтобы прийти в (0,0)
        if ($simH -gt 0.1) {
            $aRequired = ($simV * $simV) / (2.0 * $simH)
            $thrust = $totalMass * ($aRequired + $g_moon)
            $thrust = [Math]::Max(0, [Math]::Min($thrust, $maxThrust))
        } else {
            $thrust = $totalMass * $g_moon  # висение у поверхности
        }
        $accel = ($thrust / $totalMass) - $g_moon
        $simV -= $accel * $dt
        if ($simV -lt 0) { $simV = 0 }
        $simH -= $simV * $dt
        if ($simV -le 0.01 -and $simH -le 0.1) { break }
    }
    if ($simH -lt 0) { $simH = 0 }
    $trajPoints.Add([System.Drawing.PointF]::new((VtoX $simV), (HtoY $simH)))
}

# добавляем финальную точку (0,0)
$trajPoints.Add([System.Drawing.PointF]::new((VtoX 0), (HtoY 0)))

# рисуем единую пунктирную линию
if ($trajPoints.Count -ge 2) {
    $gr.DrawLines($penTraj, $trajPoints.ToArray())
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

#  Легенда
$legendX = $marginLeft + 15
$legendY = $marginTop + 10
$gr.DrawLine($penCurve, $legendX, ($legendY + 6), ($legendX + 25), ($legendY + 6))
$gr.DrawString("мгновенное включение", $fontLegend, $brushCurve, ($legendX + 30), $legendY)
$gr.DrawLine($penCurveDelay, $legendX, ($legendY + 22), ($legendX + 25), ($legendY + 22))
$gr.DrawString(("с задержкой {0}с" -f $t_delay), $fontLegend, $brushCurveDelay, ($legendX + 30), ($legendY + 16))
$gr.DrawLine($penTraj, $legendX, ($legendY + 38), ($legendX + 25), ($legendY + 38))
$gr.DrawString("траектория посадки", $fontLegend, $brushTrajectory, ($legendX + 30), ($legendY + 32))

#  Заголовок
$gr.DrawString("Включаем полную тягу чуть раньше", $fontTitle, $brushTitle,
    ($marginLeft + 15), 8)

#  Сохранение
$outputPath = Join-Path $PSScriptRoot "graph2.png"
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
