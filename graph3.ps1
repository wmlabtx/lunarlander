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
$a_thrust = $maxThrust / $totalMass     # ускорение от полной тяги
$a_net = $a_thrust - $g_moon            # чистое замедление при торможении
$t_flip = 2.0           # время разворота: тяга от -100% до +100% (с)

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
$colorZone       = [System.Drawing.Color]::FromArgb(0, 140, 50)
$colorDanger     = [System.Drawing.Color]::FromArgb(0, 255, 0)
$colorAxisLabel  = [System.Drawing.Color]::FromArgb(60, 160, 60)
$colorTrajectory = [System.Drawing.Color]::FromArgb(50, 255, 50)

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

#  Моделирование траектории: разгон дюзами вверх, разворот, торможение
# Фаза 0: разгон — тяга направлена вниз (дюзы вверх), a = g + F/m
# Фаза 1: разворот за t_flip — тяга линейно от +F (вниз) до -F (вверх)
#          thrust_down = F * (1 - 2*tau/t_flip)
# Фаза 2: адаптивное торможение к (0,0)

$dt = 0.02
$simV = 0.0
$simH = $hMax
$simPhase = 0
$flipTime = 0.0

# Функция: высота, необходимая для разворота + торможения при текущей скорости V
# Во время разворота (аналитически):
#   V_after = V + g*t_flip  (чистый эффект тяги за разворот = 0, остаётся только гравитация)
#   H_fall  = V*t_flip + g*t_flip²/2 + (F/m)*t_flip²/6  (тяга ещё частично толкает вниз)
# После разворота: H_brake = V_after² / (2*a_net)
function Get-FlipHeight([double]$V) {
    $vAfter = $V + $g_moon * $t_flip
    $hFall  = $V * $t_flip + $g_moon * $t_flip * $t_flip / 2.0 + $a_thrust * $t_flip * $t_flip / 6.0
    $hBrake = ($vAfter * $vAfter) / (2.0 * $a_net)
    return $hFall + $hBrake
}

$trajPoints = New-Object System.Collections.Generic.List[System.Drawing.PointF]
$trajPoints.Add([System.Drawing.PointF]::new((VtoX $simV), (HtoY $simH)))

while ($simH -gt 0 -and $simV -ge 0 -and $simV -lt $vMax) {
    if ($simPhase -eq 0) {
        # разгон: тяга + гравитация вниз
        $hNeeded = Get-FlipHeight $simV
        if ($simH -le $hNeeded) {
            $simPhase = 1
            $flipTime = 0.0
        }
        $accelDown = $g_moon + $a_thrust   # обе силы вниз
        $simV += $accelDown * $dt
        $simH -= $simV * $dt
    }
    elseif ($simPhase -eq 1) {
        # разворот: тяга линейно от +F(вниз) до -F(вверх) за t_flip
        $flipTime += $dt
        $frac = [Math]::Min($flipTime / $t_flip, 1.0)
        # thrust_down_fraction: 1 -> -1
        $thrustDownFrac = 1.0 - 2.0 * $frac
        $accelDown = $g_moon + $a_thrust * $thrustDownFrac
        $simV += $accelDown * $dt
        if ($simV -lt 0) { $simV = 0 }
        $simH -= $simV * $dt
        if ($flipTime -ge $t_flip) {
            $simPhase = 2
        }
    }
    else {
        # адаптивное торможение: a_required = V²/(2H)
        if ($simH -gt 0.1) {
            $aRequired = ($simV * $simV) / (2.0 * $simH)
            $thrust = $totalMass * ($aRequired + $g_moon)
            $thrust = [Math]::Max(0, [Math]::Min($thrust, $maxThrust))
        } else {
            $thrust = $totalMass * $g_moon
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

$trajPoints.Add([System.Drawing.PointF]::new((VtoX 0), (HtoY 0)))

if ($trajPoints.Count -ge 2) {
    $gr.DrawLines($penTraj, $trajPoints.ToArray())
}

#  Надписи зон
$sfZone = New-Object System.Drawing.StringFormat
$sfZone.Alignment = [System.Drawing.StringAlignment]::Center

$gr.DrawString("безопасная зона", $fontZone, $brushZone,
    (VtoX 20), (HtoY 1000), $sfZone)

$gr.DrawString("катастрофа", $fontZone, $brushDanger,
    (VtoX 60), (HtoY 450), $sfZone)

#  Легенда
$legendX = $marginLeft + 15
$legendY = $marginTop + 40
$gr.DrawLine($penCurve, $legendX, ($legendY + 6), ($legendX + 25), ($legendY + 6))
$gr.DrawString("идеальный спуск", $fontLegend, $brushCurve, ($legendX + 30), $legendY)
$gr.DrawLine($penTraj, $legendX, ($legendY + 22), ($legendX + 25), ($legendY + 22))
$gr.DrawString("разгон + разворот + торможение", $fontLegend, $brushTrajectory, ($legendX + 30), ($legendY + 16))

#  Заголовок
$gr.DrawString("Быстрая посадка", $fontTitle, $brushTitle,
    ($marginLeft + 120), 8)

#  Сохранение
$outputPath = Join-Path $PSScriptRoot "graph3.png"
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
