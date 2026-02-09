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
Функция для отрисовки шкалы символами ASCII
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

    [int]$filled = [Math]::Round($ratio * $width)
    [int]$empty = $width - $filled

    $bar = [string]"#" * $filled
    $bar += [string][char]0x00B7 * $empty

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

    $color = if ($Height -lt 2) { "DarkGreen" } elseif ($Height -lt 10) { "DarkGreen" } else { "Green" }
    Write-Host ("ВЫСОТА:     {0,6:F1} м   " -f $Height) -NoNewline -ForegroundColor $color
    $hBar = Format-Bar $Height $HeightMax 15
    Write-Host $hBar -ForegroundColor $color

    $vAbs = [Math]::Abs($Velocity)
    $color = if ($vAbs -gt 100) { "DarkGreen" } elseif ($vAbs -gt 45) { "DarkGreen" } else { "Green" }
    Write-Host ("СКОРОСТЬ:   {0,6:F1} м/с " -f $Velocity) -NoNewline -ForegroundColor $color
    $vBar = Format-Bar $vAbs $VelocityMax 15
    Write-Host $vBar -ForegroundColor $color

    $color = if ($ThrustPct -lt 10) { "Green" } elseif ($ThrustPct -le 60) { "Green" } else { "DarkGreen" }
    Write-Host ("ТЯГА:       {0,6:F1}%    " -f $ThrustPct) -NoNewline -ForegroundColor $color
    $tBar = Format-Bar $ThrustPct 100.0 15
    Write-Host $tBar -ForegroundColor $color

    $color = if ($Acceleration -gt 1.0) { "DarkGreen" } elseif ($Acceleration -gt 0.2) { "Green" } else { "Green" }
    Write-Host ("УСКОРЕНИЕ:  {0,6:F2} g   " -f $Acceleration) -NoNewline -ForegroundColor $color
    $gBar = Format-Bar $Acceleration $AccelerationMax 15
    Write-Host $gBar -ForegroundColor $color

    $color = if ($FuelMass -lt 200) { "DarkGreen" } elseif ($FuelMass -lt 500) { "DarkGreen" } else { "Green" }
    Write-Host ("ТОПЛИВО:    {0,6:F0} кг  " -f $FuelMass) -NoNewline -ForegroundColor $color
    $fBar = Format-Bar $FuelMass $FuelMassMax 15
    Write-Host $fBar -ForegroundColor $color

    Write-Host "ДВИГАТЕЛЬ: " -NoNewline -ForegroundColor Green
    if ($EngineState -eq [EngineStatus]::Active) {
        Write-Host ("* Работает         ") -ForegroundColor Green
    }
    elseif ($EngineState -eq [EngineStatus]::Throttling) {
        Write-Host ("* Регулировка тяги ") -ForegroundColor Green
    }
    elseif ($EngineState -eq [EngineStatus]::Ignition) {
        Write-Host ("~ Зажигание        ") -ForegroundColor DarkGreen
    }
    elseif ($EngineState -eq [EngineStatus]::Cutoff) {
        Write-Host ("~ Гашение          ") -ForegroundColor DarkGreen
    }
    else {
        Write-Host ("  Выключен         ") -ForegroundColor DarkGreen
    }
}

<#
.SYNOPSIS
Отрисовка оси времени (мелкие и крупные засечки с подписями)
#>
function New-TimeAxis {
    param(
        [Parameter(Mandatory = $true)]
        $Graphics,
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
        $Graphics.DrawString("{0:F0}" -f $ts, $fontSmall, $brushAxis, $xPos - 10, $Y + $Height + 2)
    }
}