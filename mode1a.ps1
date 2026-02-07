# Состояние двигателя

enum EngineStatus {
    Off        # Двигатель выключен
    Ignition   # Зажигание двигателя
    Throttling # Выход на заданный уровень тяги
    Active     # Работа на стабильной тяге
    Cutoff     # Гашение двигателя
}

# Физические константы

class Constants {
    # Физические константы
    static [double]$MoonGravity = 1.625  # м/с²
    static [double]$EarthGravity = 9.807  # м/с²

    # Параметры посадочного модуля и двигателя
    static [double]$DryMass = 4500.0         # масса посадочного модуля LM-5 без топлива (кг)
    static [double]$MaxThrust = 45000.0      # максимальная тяга двигателя DPS LM (Н)
    static [double]$MinThrustPct = 10.0      # минимально регулируемая тяга двигателя (%)
    static [double]$MaxThrustPct = 65.0      # максимально регулируемая тяга двигателя (%)
    static [double]$HeightCutoff = 0.4       # высота отключения двигателя (м)
    static [double]$IgnitionTime = 0.7       # время зажигания двигателя (с)
    static [double]$CutoffTime = 0.6         # время отключения двигателя до полной остановки тяги (с)
    static [double]$ThrottleLag = 0.5        # время реакции двигателя на изменение команды тяги (с)

    # Параметры симуляции
    static [double]$TimeStep = 0.1           # шаг симуляции (сек)

    # Стартовые условия
    static [double]$FuelStart = 10500        # начальная масса топлива LM-5 (кг)
    static [double]$HeightStart = 3000.0     # начальная высота (м)
    static [double]$VelocityStart = 0.0      # начальная вертикальная скорость (м/с)
    static [double]$AccelerationStart = 0.0  # начальное ускорение (м/с²)
    static [double]$ThrustPctStart = 0.0          # начальная тяга (%)
    static [EngineStatus]$EngineStateStart = 
      [EngineStatus]::Off                    # начальное состояние двигателя
}

# Телеметрия

class TelemetryRecord {
    [double]$Time
    [double]$Height
    [double]$Velocity
    [double]$ThrustPct
    [double]$Acceleration
    [double]$FuelMass
    [EngineStatus]$EngineState
}

# Переменные симуляции

class Situation {
    static [double]$Time                   # время (с)
    static [double]$Height                 # высота (м)
    static [double]$Velocity               # вертикальная скорость (м/с)
    static [double]$Acceleration           # текущее ускорение (м/с²)    
    static [double]$FuelMass               # масса топлива (кг)
    static [EngineStatus]$EngineState      # состояние двигателя
    static [double]$Thrust                 # реальная тяга (Н)
    static [double]$ThrustCommandedPct     # заказанная тяга (0 - 100)
    static [double]$TimeThrustStart        # время начала изменения тяги (с)
    static [double]$TimeThrustEnd          # время завершения изменения тяги (с)
    static [double]$ThrustStart            # тяга в начале изменения (Н)
    static [double]$ThrustEnd              # тяга в конце изменения (Н)
    static [bool]$ContactLight             # флаг касания щупов
}

# Параметры прошивки

class Firmware {
    static [double]$HeightGate1 = 1750.0   # этап 2: включение двигателя на 100% (м)
    static [double]$VelocityGate2 = -15.0  # этап 3: переход на дроссельную тягу 50-60% (м/с)
    static [double]$HeightGate3  = 20.0    # этап 4: финальное замедление (м)
    static [double]$VelocityGate3 = -1.0   # целевая скорость после торможения (м/с)    
    static [double]$VelocityGate4 = -0.1   # целевая скорость на cutoff (м/с)
}

. "$PSScriptRoot\functions.ps1"

# Начало сценария

Clear-Host
Write-Host "Lunar landing: Mode 1 - Manual landing" -ForegroundColor Cyan
Read-Host -Prompt "Press ENTER to start the landing..."

# Стартовые параметры

[Situation]::Time = 0.0
[Situation]::Height = [Constants]::HeightStart
[Situation]::Velocity = [Constants]::VelocityStart
[Situation]::Acceleration = [Constants]::AccelerationStart
[Situation]::FuelMass = [Constants]::FuelStart
[Situation]::EngineState = [Constants]::EngineStateStart
[Situation]::Thrust = [Constants]::MaxThrust *  ([Constants]::ThrustPctStart / 100.0)
[Situation]::ThrustCommandedPct = [Constants]::ThrustPctStart
[Situation]::TimeThrustStart = 0.0
[Situation]::TimeThrustEnd = 0.0
[Situation]::ThrustStart = 0.0
[Situation]::ThrustEnd = 0.0
[Situation]::ContactLight = $false

$Telemetry = [System.Collections.Generic.List[TelemetryRecord]]::new()

#
# Цикл симуляции
#

[Console]::CursorVisible = $false

while ([Situation]::Height -gt 0) {
    # сохраняем телеметрию
    $record = [TelemetryRecord]::new()
    $record.Time         = [Situation]::Time
    $record.Height       = [Situation]::Height
    $record.Velocity     = [Situation]::Velocity
    $record.ThrustPct    = [Situation]::ThrustCommandedPct
    $record.Acceleration = [Situation]::Acceleration
    $record.FuelMass     = [Situation]::FuelMass
    $record.EngineState  = [Situation]::EngineState
    $Telemetry.Add($record)

    # выводим индикаторы
    [Console]::SetCursorPosition(0, 1)
    Format-Scales `
        -Height ([Situation]::Height) `
        -HeightMax ([Constants]::HeightStart) `
        -Velocity ([Situation]::Velocity) `
        -VelocityMax 100.0 `
        -ThrustPct ([Situation]::ThrustCommandedPct) `
        -Acceleration ([Situation]::Acceleration) `
        -AccelerationMax 1.0 `
        -FuelMass ([Situation]::FuelMass) `
        -FuelMassMax ([Constants]::FuelStart) `
        -EngineState ([Situation]::EngineState)

    # обновление состояния двигателя
    if ([Situation]::EngineState -eq [EngineStatus]::Off) {
        # двигатель выключен
        [Situation]::Thrust = 0.0        
    }
    elseif ([Situation]::EngineState -eq [EngineStatus]::Ignition) {
        # двигатель в процессе зажигания
        [Situation]::Thrust = 0.0
        if ([Situation]::Time -ge [Situation]::TimeThrustEnd) {
            # зажигание завершено
            [Situation]::EngineState = [EngineStatus]::Throttling
            [Situation]::TimeThrustStart = [Situation]::Time
            [Situation]::TimeThrustEnd = [Situation]::Time + [Constants]::ThrottleLag
            [Situation]::ThrustStart = 0.0
            [Situation]::ThrustEnd = ([Constants]::MaxThrust * ( [Situation]::ThrustCommandedPct / 100.0 ))
         }
    }
    elseif ([Situation]::EngineState -eq [EngineStatus]::Throttling) {
        # двигатель в процессе выхода на заданный уровень тяги
        if ([Situation]::Time -ge [Situation]::TimeThrustEnd) {
            # выход на заданный уровень тяги завершен
            [Situation]::EngineState = [EngineStatus]::Active
            [Situation]::Thrust = [Situation]::ThrustEnd
         }
         else {
            # вычисляем текущую тягу с плавным изменением
            [Situation]::Thrust = Get-ThrustEasing `
                -TimeThrustStart ([Situation]::TimeThrustStart) `
                -TimeThrustEnd ([Situation]::TimeThrustEnd) `
                -CurrentTime ([Situation]::Time) `
                -ThrustStart ([Situation]::ThrustStart) `
                -ThrustEnd ([Situation]::ThrustEnd)
         }
    }
    elseif ([Situation]::EngineState -eq [EngineStatus]::Active) {
        # двигатель работает в стабильном режиме
    }
    elseif ([Situation]::EngineState -eq [EngineStatus]::Cutoff) {
        # двигатель в процессе выключения
        if ([Situation]::Time -ge [Situation]::TimeThrustEnd) {
            # выключение завершено
            [Situation]::EngineState = [EngineStatus]::Off
            [Situation]::Thrust = 0.0
        }
        else {
            # вычисляем текущую тягу с плавным изменением
            [Situation]::Thrust = Get-ThrustEasing `
                -TimeThrustStart ([Situation]::TimeThrustStart) `
                -TimeThrustEnd ([Situation]::TimeThrustEnd) `
                -CurrentTime ([Situation]::Time) `
                -ThrustStart ([Situation]::ThrustStart) `
                -ThrustEnd ([Situation]::ThrustEnd)
        }
    }

    # проверка на исчрепление топлива
    if ([Situation]::FuelMass -le 0) {
        [Situation]::FuelMass = 0.0
        [Situation]::EngineState = [EngineStatus]::Off
        [Situation]::Thrust = 0.0
    }

    # проверка на приближение к поверхности
    if (-not [Situation]::ContactLight -and [Situation]::Height -le [Constants]::HeightCutoff) {
        [Situation]::ContactLight = $true
        # если двигатель ещё не выключен - гасим его
        if ([Situation]::EngineState -ne [EngineStatus]::Cutoff -and
            [Situation]::EngineState -ne [EngineStatus]::Off) {
            [Situation]::EngineState = [EngineStatus]::Cutoff
            [Situation]::ThrustCommandedPct = 0.0
            [Situation]::TimeThrustStart = [Situation]::Time
            [Situation]::TimeThrustEnd = [Situation]::Time + [Constants]::CutoffTime
            [Situation]::ThrustStart = [Situation]::Thrust
            [Situation]::ThrustEnd = 0.0
        }
    }

    #
    # А вот это наша прошивка
    # Анализируем ситуацию и вычисляем команду тяги $ThrustCommandedPct
    # При необоходимости меняем состояние двигателя
    #

    # после срабатывания щупов прошивка не вмешивается — двигатель гасится штатно
    if (-not [Situation]::ContactLight) {

        $H = [Situation]::Height
        $V = [Situation]::Velocity

        if ($H -gt [Firmware]::HeightGate1) {
            # этап 1: выше Gate1 — свободное падение, двигатель не нужен
            $pctRequired = 0.0
        }
        elseif ($V -lt [Firmware]::VelocityGate2) {
            # этап 2: скорость слишком высокая — полная тяга, тормозим до VelocityGate2
            $pctRequired = 100.0
        }
        else {
            # этапы 3-4: адаптивное управление тягой по P-регулятору
            # целевая скорость — линейная интерполяция по высоте

            if ($H -gt [Firmware]::HeightGate3) {
                # этап 3: от текущей высоты до HeightGate3
                # целевая скорость: от VelocityGate2 (-25) до VelocityGate3 (-3)
                $frac = ($H - [Firmware]::HeightGate3) / ([Firmware]::HeightGate1 - [Firmware]::HeightGate3)
                $targetVelocity = [Firmware]::VelocityGate3 + `
                    ([Firmware]::VelocityGate2 - [Firmware]::VelocityGate3) * $frac
            }
            else {
                # этап 4: от HeightGate3 до HeightCutoff
                # целевая скорость: от VelocityGate3 (-3) до VelocityGate4 (-0.3)
                $frac = ($H - [Constants]::HeightCutoff) / `
                    ([Firmware]::HeightGate3 - [Constants]::HeightCutoff)
                $targetVelocity = [Firmware]::VelocityGate4 + `
                    ([Firmware]::VelocityGate3 - [Firmware]::VelocityGate4) * $frac
            }

            # ошибка скорости: отрицательная = падаем быстрее, чем нужно
            $velocityError = $V - $targetVelocity
            $totalMass = [Constants]::DryMass + [Situation]::FuelMass

            if ($velocityError -ge 0) {
                # скорость ниже целевой — двигатель не нужен
                $pctRequired = 0.0
            }
            else {
                # тяга висения как базовая
                $thrustHover = $totalMass * [Constants]::MoonGravity

                # P-коррекция: чем больше ошибка, тем больше тяга
                $Kp = 2000.0
                $thrustRequired = $thrustHover - $Kp * $velocityError

                # переводим в проценты
                $pctRequired = $thrustRequired * 100.0 / [Constants]::MaxThrust
            }
        }

        # ограничиваем диапазон дросселируемой тяги
        if ($pctRequired -lt [Constants]::MinThrustPct) {
            if (
                [Situation]::EngineState -eq [EngineStatus]::Off -or
                [Situation]::EngineState -eq [EngineStatus]::Ignition
            ) {
                # двигатель выключен или в процессе зажигания — оставляем 0
                $pctRequired = 0.0
            }
            else {
                # двигатель работает — ставим минимум тяги, чтобы не заглох
                $pctRequired = [Constants]::MinThrustPct
            }
        }

        if ($pctRequired -gt 90.0) {
            # критическая потребность в тяге — полная тяга
            $pctRequired = 100.0
        }
        elseif ($pctRequired -gt [Constants]::MaxThrustPct) {
            # мёртвая зона дросселя 66-90% — зажимаем на максимум диапазона
            $pctRequired = [Constants]::MaxThrustPct
        }

        # если двигатель выключен и нужна тяга — запускаем зажигание
        if ([Situation]::EngineState -eq [EngineStatus]::Off -and $pctRequired -gt 0.0) {
            [Situation]::EngineState = [EngineStatus]::Ignition
            [Situation]::ThrustCommandedPct = $pctRequired
            [Situation]::TimeThrustStart = [Situation]::Time
            [Situation]::TimeThrustEnd = [Situation]::Time + [Constants]::IgnitionTime
            [Situation]::ThrustStart = [Situation]::Thrust
            [Situation]::ThrustEnd = [Constants]::MaxThrust * ($pctRequired / 100.0)
        }
        elseif ($pctRequired -ne [Situation]::ThrustCommandedPct) {
            # если заказанная тяга изменилась — переходим в режим Throttling
            [Situation]::EngineState = [EngineStatus]::Throttling
            [Situation]::ThrustCommandedPct = $pctRequired
            [Situation]::TimeThrustStart = [Situation]::Time
            [Situation]::TimeThrustEnd = [Situation]::Time + [Constants]::ThrottleLag
            [Situation]::ThrustStart = [Situation]::Thrust
            [Situation]::ThrustEnd = [Constants]::MaxThrust * ($pctRequired / 100.0)
        }

    } # if (-not ContactLight)

    #
    # Конец прошивки
    #

    # физика: обновляем состояние на один шаг TimeStep
    $dt = [Constants]::TimeStep
    $totalMass = [Constants]::DryMass + [Situation]::FuelMass

    # расход топлива по текущему проценту тяги
    $thrustPct = [Situation]::Thrust * 100.0 / [Constants]::MaxThrust
    $fuelFlow = Get-LMFuelFlow $thrustPct
    [Situation]::FuelMass -= $fuelFlow * $dt
    if ([Situation]::FuelMass -lt 0) { 
        [Situation]::FuelMass = 0.0 
    }

    # показания акселерометра в земных g (в свободном падении = 0, при висении = MoonG/EarthG)
    [Situation]::Acceleration = [Situation]::Thrust / ($totalMass * [Constants]::EarthGravity)

    # кинематическое ускорение для интегрирования
    $aNet = ([Situation]::Thrust / $totalMass) - [Constants]::MoonGravity

    # сохраняем состояние до интегрирования (для интерполяции касания)
    $heightBefore = [Situation]::Height
    $velocityBefore = [Situation]::Velocity

    # интегрирование: скорость и высота
    [Situation]::Velocity += $aNet * $dt
    [Situation]::Height   += [Situation]::Velocity * $dt
    [Situation]::Time     += $dt

    Start-Sleep -Milliseconds 20
}

[Console]::CursorVisible = $true

# Вычисляем показатели в момент посадки

# интерполяция скорости в момент касания (H=0) между двумя последними точками
$f = $heightBefore / ($heightBefore - [Situation]::Height)
$RecordedTouchdownVelocity = $velocityBefore + $f * ([Situation]::Velocity - $velocityBefore)
$RecordedMaxVelocity = ($Telemetry | ForEach-Object { [Math]::Abs($_.Velocity) } | Measure-Object -Maximum).Maximum
$RecordedMaxAcceleration = ($Telemetry | ForEach-Object { $_.Acceleration } | Measure-Object -Maximum).Maximum

# Финальное состояние: модуль стоит на грунте

[Situation]::Height = 0.0
[Situation]::Velocity = 0.0

# Обновляем финальный дисплей
[Console]::SetCursorPosition(0, 1)
Format-Scales `
    -Height ([Situation]::Height) `
    -HeightMax ([Constants]::HeightStart) `
    -Velocity ([Situation]::Velocity) `
    -VelocityMax 100.0 `
    -ThrustPct ([Situation]::ThrustCommandedPct) `
    -Acceleration ([Situation]::Acceleration) `
    -AccelerationMax 1.0 `
    -FuelMass ([Situation]::FuelMass) `
    -FuelMassMax ([Constants]::FuelStart) `
    -EngineState ([Situation]::EngineState)
Write-Host ""
Write-Host ("Touchdown velocity:    {0,7:F2} m/s" -f $RecordedTouchdownVelocity)
Write-Host ("Maximum velocity:      {0,7:F2} m/s" -f $RecordedMaxVelocity)
Write-Host ("Landing duration:      {0,7:F2} s" -f ([Situation]::Time))
Write-Host ("Fuel consumed:         {0,7:F2} kg" -f ([Constants]::FuelStart - [Situation]::FuelMass))
Write-Host ("Maximum acceleration:  {0,7:F2} g" -f $RecordedMaxAcceleration)
Write-Host ""

# Сохраняем телеметрию в файл
$logPath = Join-Path $PSScriptRoot "mode1a.log"
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("Time;Height;Velocity;ThrustPct;Acceleration;FuelMass;EngineState")
foreach ($r in $Telemetry) {
    $lines.Add(("{0:F1};{1:F1};{2:F1};{3:F1};{4:F1};{5:F1};{6}" -f $r.Time, $r.Height, $r.Velocity, $r.ThrustPct, $r.Acceleration, $r.FuelMass, $r.EngineState))
}
[System.IO.File]::WriteAllLines($logPath, $lines)
Write-Host ("Telemetry saved: " + $logPath) -ForegroundColor Green


# Генерация PNG графика телеметрии

Add-Type -AssemblyName System.Drawing

# каждая секунда = $pps пикселей
$pps = 3
$graphWidth = [int]([Situation]::Time * $pps)

# отступы
$marginLeft = 60   # для подписей оси Y
$marginRight = 20  # минимальный отступ справа
$marginBottom = 30 # для подписей оси X

# общая ширина и высота изображения
$imgWidth = $graphWidth + $marginLeft + $marginRight
$imgHeight = 390 + $marginBottom  # последний график заканчивается на y=390 (310+80)

# создаём bitmap и graphics
$bmp = New-Object System.Drawing.Bitmap($imgWidth, $imgHeight)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# фон
$g.Clear([System.Drawing.Color]::FromArgb(20, 30, 40))

# шрифты и кисти
$fontNormal = New-Object System.Drawing.Font("Consolas", 16)
$fontSmall = New-Object System.Drawing.Font("Consolas", 10)
$brushWhite = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$brushGray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Gray)
$brushDarkGray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::DarkGray)
$brushGreen = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::LimeGreen)
$brushCyan = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Cyan)
$brushYellow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Yellow)
$brushRed = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Red)

# перья для графиков
$penGrid = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50, 60, 70), 1)
$penTick = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40, 50, 55), 1)
$penOff = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 60, 60), 2)
$penIgniting = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 4)
$penRunning = New-Object System.Drawing.Pen([System.Drawing.Color]::Yellow, 2)
$penFullThrust = New-Object System.Drawing.Pen([System.Drawing.Color]::Red, 2)
$penShutdown = New-Object System.Drawing.Pen([System.Drawing.Color]::Magenta, 2)
$penG = New-Object System.Drawing.Pen([System.Drawing.Color]::LimeGreen, 2)
$penMoonG = New-Object System.Drawing.Pen([System.Drawing.Color]::Orange, 2)
$penMoonG.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash

# график 1: высота (с раскраской по состоянию двигателя)

$graphX = $marginLeft
$graphY = 30

# $graphWidth уже вычислен выше на основе времени посадки
$graphHeight = 240

$g.DrawRectangle($penGrid, $graphX, $graphY, $graphWidth, $graphHeight)
$g.DrawString("ВЫСОТА", $fontNormal, $brushWhite, $graphX, $graphY - 24)

# сетка для графика высоты
for ($i = 0; $i -le 5; $i++) {
    $yPos = $graphY + ($graphHeight / 5) * $i
    $g.DrawLine($penGrid, $graphX, $yPos, $graphX + $graphWidth, $yPos)
    $val = [Constants]::HeightStart - ([Constants]::HeightStart / 5) * $i
    $g.DrawString("{0:F0}м" -f $val, $fontSmall, $brushGray, $graphX - 50, $yPos - 9)
}

# ось времени для графика высоты
$tTotal = ($Telemetry | Select-Object -ExpandProperty Time)[-1]
New-TimeAxis -Graphics $g -X $graphX -Y $graphY -Width $graphWidth -Height $graphHeight -TTotal $tTotal

# рисуем линию высоты с раскраской по состоянию двигателя
$points = $Telemetry | Select-Object -ExpandProperty Height
$timePoints = $Telemetry | Select-Object -ExpandProperty Time
$engineStates = $Telemetry | Select-Object -ExpandProperty EngineState
$thrustValues = $Telemetry | Select-Object -ExpandProperty ThrustPct

for ($i = 0; $i -lt ($points.Count - 1); $i++) {
    $t1 = $timePoints[$i]
    $t2 = $timePoints[$i + 1]
    $h1 = $points[$i]
    $h2 = $points[$i + 1]
    $state = $engineStates[$i]
    $thrust = $thrustValues[$i]

    $x1 = $graphX + ($t1 / $timePoints[-1]) * $graphWidth
    $x2 = $graphX + ($t2 / $timePoints[-1]) * $graphWidth
    $y1 = $graphY + $graphHeight - ($h1 / [Constants]::HeightStart) * $graphHeight
    $y2 = $graphY + $graphHeight - ($h2 / [Constants]::HeightStart) * $graphHeight

    # выбираем перо в зависимости от состояния двигателя и тяги
    $pen = $penOff
    if ($state -eq [EngineStatus]::Ignition) {
        $pen = $penIgniting
    }
    elseif ($state -eq [EngineStatus]::Active -or $state -eq [EngineStatus]::Throttling) {
        if ($thrust -ge 90) {
            $pen = $penFullThrust
        }
        else {
            $pen = $penRunning
        }
    }
    elseif ($state -eq [EngineStatus]::Cutoff) {
        $pen = $penShutdown
    }

    $g.DrawLine($pen, $x1, $y1, $x2, $y2)
}

# статистика в правом верхнем углу графика высоты
$statsX = $graphX + $graphWidth - 180
$statsY = $graphY + 10
$g.DrawString("СТАТИСТИКА ПОЛЁТА", $fontSmall, $brushWhite, $statsX, $statsY)
$g.DrawString(("Время:    {0,5:F1} сек" -f [Situation]::Time), $fontSmall, $brushGreen, $statsX, $statsY + 18)
$g.DrawString(("Топливо:  {0,5:F1} кг" -f ([Constants]::FuelStart - [Situation]::FuelMass)), $fontSmall, $brushCyan, $statsX, $statsY + 36)
$g.DrawString(("Макс g:   {0,5:F2} g" -f $RecordedMaxAcceleration), $fontSmall, $brushYellow, $statsX, $statsY + 54)
$g.DrawString(("Макс V:   {0,5:F2} м/с" -f $RecordedMaxVelocity), $fontSmall, $brushWhite, $statsX, $statsY + 72)
$g.DrawString(("Касание:  {0,5:F2} м/с" -f $RecordedTouchdownVelocity), $fontSmall, $brushWhite, $statsX, $statsY + 90)

# легенда состояний двигателя
$legendX = $graphX + 30
$legendY = $graphY + $graphHeight - 90
$g.DrawLine($penOff, $legendX, $legendY, $legendX + 20, $legendY)
$g.DrawString("Выключен", $fontSmall, $brushDarkGray, $legendX + 25, $legendY - 6)
$g.DrawLine($penIgniting, $legendX, $legendY + 15, $legendX + 20, $legendY + 15)
$g.DrawString("Зажигание", $fontSmall, $brushWhite, $legendX + 25, $legendY + 9)
$g.DrawLine($penRunning, $legendX, $legendY + 30, $legendX + 20, $legendY + 30)
$g.DrawString("Регулируемая тяга", $fontSmall, $brushYellow, $legendX + 25, $legendY + 24)
$g.DrawLine($penFullThrust, $legendX, $legendY + 45, $legendX + 20, $legendY + 45)
$g.DrawString("Полная тяга", $fontSmall, $brushRed, $legendX + 25, $legendY + 39)
$g.DrawLine($penShutdown, $legendX, $legendY + 60, $legendX + 20, $legendY + 60)
$g.DrawString("Гашение", $fontSmall, $brushWhite, $legendX + 25, $legendY + 54)

# График 2: Ускорение

# рисуем линию лунного g (до отрисовки самого графика)
$gGraphX = $marginLeft
$gGraphY = 310
$gGraphWidth = $graphWidth
$gGraphHeight = 80
$gMinVal = 0

# Округляем до одной цифры после запятой в большую сторону
$gMaxVal = [Math]::Ceiling($RecordedMaxAcceleration * 10) / 10
$gRange = $gMaxVal - $gMinVal

# переводим лунное g из м/с² в земные g
$moonG_in_earth_g = [Constants]::MoonGravity / [Constants]::EarthGravity
$moonG_normalized = ($moonG_in_earth_g - $gMinVal) / $gRange
$moonG_y = $gGraphY + $gGraphHeight - ($moonG_normalized * $gGraphHeight)

# рисуем пунктирную линию
$g.DrawLine($penMoonG, $gGraphX, $moonG_y, $gGraphX + $gGraphWidth, $moonG_y)

# подпись "g"
$g.DrawString("g", $fontSmall, $brushGray, $gGraphX + 5, $moonG_y - 18)

# рамка графика
$g.DrawRectangle($penGrid, $gGraphX, $gGraphY, $gGraphWidth, $gGraphHeight)

# заголовок графика
$g.DrawString("УСКОРЕНИЕ", $fontNormal, $brushWhite, $gGraphX, $gGraphY - 24)

# сетка (шаг 0.1g)
$gDivisions = [int]($gMaxVal * 10)
for ($i = 0; $i -le $gDivisions; $i++) {
    $yPos = $gGraphY + ($gGraphHeight / $gDivisions) * $i
    $g.DrawLine($penGrid, $gGraphX, $yPos, $gGraphX + $gGraphWidth, $yPos)
    $val = $gMaxVal - 0.1 * $i
    $g.DrawString("{0:F1}g" -f $val, $fontSmall, $brushGray, $gGraphX - 50, $yPos - 9)
}

# извлекаем значения ускорения
$gPoints = $Telemetry | Select-Object -ExpandProperty Acceleration
$gTimePoints = $Telemetry | Select-Object -ExpandProperty Time

if ($gPoints.Count -ge 2) {
    # метки по оси X (секунды)
    New-TimeAxis -Graphics $g -X $gGraphX -Y $gGraphY -Width $gGraphWidth -Height $gGraphHeight -TTotal $gTimePoints[-1]

    # рисуем линию графика
    for ($i = 0; $i -lt ($gPoints.Count - 1); $i++) {
        $t1 = $gTimePoints[$i]
        $t2 = $gTimePoints[$i + 1]
        $v1 = $gPoints[$i]
        $v2 = $gPoints[$i + 1]

        $x1 = $gGraphX + ($t1 / $gTimePoints[-1]) * $gGraphWidth
        $x2 = $gGraphX + ($t2 / $gTimePoints[-1]) * $gGraphWidth
        $y1 = $gGraphY + $gGraphHeight - (($v1 - $gMinVal) / $gRange) * $gGraphHeight
        $y2 = $gGraphY + $gGraphHeight - (($v2 - $gMinVal) / $gRange) * $gGraphHeight

        $g.DrawLine($penG, $x1, $y1, $x2, $y2)
    }
}

# Сохранение

$outputPath = Join-Path $PSScriptRoot "mode1a.png"

try {
    $bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()

    if (Test-Path $outputPath) {
        Write-Host ("Graph saved: " + $outputPath) -ForegroundColor Green
    }
    else {
        Write-Host "Error: file was not created" -ForegroundColor Red
    }
}
catch {
    Write-Host ("Error saving graph: " + $_.Exception.Message) -ForegroundColor Red
    $g.Dispose()
    $bmp.Dispose()
}