<#
.SYNOPSIS
Расчет расхода топлива кг/с в зависимости от процента тяги двигателя LM-5
.DESCRIPTION
Реальные данные LM-5:
 10 - 1.70; 65 - 10.1; 100 - 15.3
При этом значения [1 - 9] и [66 – 93] запрещены конструкцией двигателя DPS
#>
function Get-LMFuelFlow {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [double]$ThrottlePercentage)

    $flowRate = $ThrottlePercentage * (3.7697 + 0.14718 * $ThrottlePercentage) / (20.832 + $ThrottlePercentage)
    return $flowRate
}

<#
.SYNOPSIS
Функция плавного старта и плавного торможения (easing)
#>
function Get-ThrustEasing {
    param(
        [Parameter(Mandatory = $true)]
        [double]$TimeThrustStart,
        [Parameter(Mandatory = $true)]
        [double]$TimeThrustEnd,
        [Parameter(Mandatory = $true)]
        [double]$CurrentTime,
        [Parameter(Mandatory = $true)]
        [double]$ThrustStart,
        [Parameter(Mandatory = $true)]
        [double]$ThrustEnd
    )

    [double]$X = ($CurrentTime - $TimeThrustStart) / ($TimeThrustEnd - $TimeThrustStart)
    # S-кривая на основе косинуса: плавный старт и плавное торможение
    [double]$Y = (1 - [Math]::Cos($X * [Math]::PI)) / 2
    [double]$Thrust = $ThrustStart + ($ThrustEnd - $ThrustStart) * $Y
    return $Thrust
}

<#
.SYNOPSIS
Функция для отрисовки шкалы специальными символами Fira Code
#>
function Format-Bar {
    param(
        [double]$value,
        [double]$max,
        [int]$width
    )

    [double]$division = [double]$value / [double]$max
    [double]$ratio = $division
    if ($ratio -lt 0) { $ratio = 0.0 }
    if ($ratio -gt 1) { $ratio = 1.0 }

    [int]$widthInner = $width - 2  # -2 для символов границ
    [int]$filled = [Math]::Round($ratio * $widthInner)
    [int]$empty = $widthInner - $filled

    if ($ratio -gt 0) {
        $bar = [char]0xEE03  # начало: значение > 0
    }
    else {
        $bar = [char]0xEE00  # начало: значение = 0
    }

    $bar += [string]([char]0xEE04) * $filled # заполненные блоки
    $bar += [string]([char]0xEE01) * $empty  # пустые блоки

    if ($ratio -ge 1) {
        $bar += [char]0xEE05  # конец: значение = max
    }
    else {
        $bar += [char]0xEE02  # конец: значение < max
    }

    return $bar
}

<#
.SYNOPSIS
Отрисовка всех шкал (высота, скорость, тяга, ускорение, топливо) и статуса двигателя с цветовой индикацией
#>
function Format-Scales {
    param(
        [double]$Height,
        [double]$HeightMax,
        [double]$Velocity,
        [double]$VelocityMax,
        [double]$ThrustPct,
        [double]$Acceleration,
        [double]$AccelerationMax,
        [double]$FuelMass,
        [double]$FuelMassMax,
        [EngineStatus]$EngineState
    )

    $color = if ($Height -lt 2) { "Red" } elseif ($Height -lt 10) { "Yellow" } else { "White" }
    Write-Host ("ALT:        {0,6:F1} m   " -f $Height) -NoNewline -ForegroundColor $color
    $hBar = Format-Bar $Height $HeightMax 15
    Write-Host $hBar -ForegroundColor $color

    $vAbs = [Math]::Abs($Velocity)
    $color = if ($vAbs -gt 100) { "Red" } elseif ($vAbs -gt 45) { "Yellow" } else { "White" }
    Write-Host ("VEL:        {0,6:F1} m/s " -f $Velocity) -NoNewline -ForegroundColor $color
    $vBar = Format-Bar $vAbs $VelocityMax 15
    Write-Host $vBar -ForegroundColor $color

    $color = if ($ThrustPct -lt 10) { "White" } elseif ($ThrustPct -le 60) { "Yellow" } else { "Red" }
    Write-Host ("THR:        {0,6:F1}%    " -f $ThrustPct) -NoNewline -ForegroundColor $color
    $tBar = Format-Bar $ThrustPct 100.0 15
    Write-Host $tBar -ForegroundColor $color

    $color = if ($Acceleration -gt 1.0) { "Red" } elseif ($Acceleration -gt 0.2) { "Yellow" } else { "White" }
    Write-Host ("ACC:        {0,6:F2} g   " -f $Acceleration) -NoNewline -ForegroundColor $color
    $gBar = Format-Bar $Acceleration $AccelerationMax 15
    Write-Host $gBar -ForegroundColor $color

    $color = if ($FuelMass -lt 200) { "Red" } elseif ($FuelMass -lt 500) { "Yellow" } else { "White" }
    Write-Host ("FUEL:       {0,6:F0} kg  " -f $FuelMass) -NoNewline -ForegroundColor $color
    $fBar = Format-Bar $FuelMass $FuelMassMax 15
    Write-Host $fBar -ForegroundColor $color

    Write-Host "ENGINE:    " -NoNewline -ForegroundColor White
    if ($EngineState -eq [EngineStatus]::Active) {
        Write-Host ([char]0x25CF + " Active    ") -ForegroundColor White
    }
    elseif ($EngineState -eq [EngineStatus]::Throttling) {
        Write-Host ([char]0x25CF + " Throttling") -ForegroundColor White
    }
    elseif ($EngineState -eq [EngineStatus]::Ignition) {
        Write-Host ([char]0x25D0 + " Ignition  ") -ForegroundColor Yellow
    }
    elseif ($EngineState -eq [EngineStatus]::Cutoff) {
        Write-Host ([char]0x25D1 + " Cutoff    ") -ForegroundColor Yellow
    }
    else {
        Write-Host ([char]0x25CB + " Off       ") -ForegroundColor DarkGray
    }
}

<#
.SYNOPSIS
Отрисовка оси времени (мелкие и крупные засечки с подписями)
#>
function New-TimeAxis {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory = $true)]
        [double]$X,
        [Parameter(Mandatory = $true)]
        [double]$Y,
        [Parameter(Mandatory = $true)]
        [double]$Width,
        [Parameter(Mandatory = $true)]
        [double]$Height,
        [Parameter(Mandatory = $true)]
        [double]$TTotal
    )

    # мелкие засечки каждую секунду (короткие линии снизу графика)
    for ($ts = 1; $ts -lt $TTotal; $ts++) {
        $xPos = $X + ($ts / $TTotal) * $Width
        $Graphics.DrawLine($penTick, $xPos, $Y + $Height - 4, $xPos, $Y + $Height)
    }

    # сетка каждые 10 секунд
    for ($ts = 10; $ts -lt $TTotal; $ts += 10) {
        $xPos = $X + ($ts / $TTotal) * $Width
        $Graphics.DrawLine($penTick, $xPos, $Y, $xPos, $Y + $Height)
    }

    # крупные засечки с подписями каждые 10 секунд
    for ($ts = 10; $ts -lt $TTotal; $ts += 10) {
        $xPos = $X + ($ts / $TTotal) * $Width
        $Graphics.DrawLine($penGrid, $xPos, $Y, $xPos, $Y + $Height)
        $Graphics.DrawString("{0:F0}" -f $ts, $fontSmall, $brushGray, $xPos - 10, $Y + $Height + 2)
    }
}