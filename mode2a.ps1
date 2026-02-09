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
    static [double]$IgnitionTime = 0.7       # время включения двигателя (с)
    static [double]$CutoffTime = 0.6         # время отключения двигателя до полной остановки тяги (с)
    static [double]$ThrottleLag = 0.5        # время реакции двигателя на изменение команды тяги (с)

    # Параметры симуляции
    static [double]$TimeStep = 0.1           # шаг симуляции (сек)

    # Стартовые условия
    static [double]$FuelStart = 10500        # начальная масса топлива LM-5 (кг)
    static [double]$HeightStart = 3000.0     # начальная высота (м)
    static [double]$VelocityStart = 0.0      # начальная вертикальная скорость (м/с)
    static [double]$AccelerationStart = 0.0  # начальное ускорение (м/с²)
    static [double]$ThrustPctStart = 0.0     # начальная тяга (%)
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
    static [double]$TouchdownVelocity = -0.3   # целевая скорость при касании (м/с)
    static [double]$SafetyMargin = 1.10        # запас высоты для начала торможения (10%)
}

. "$PSScriptRoot\functions.ps1"

# Начало сценария

Clear-Host
Write-Host "Посадка на Луну по G-FOLD" -ForegroundColor Green
Write-Host "Нажмите ENTER для начала посадки..." -ForegroundColor Green -NoNewline
Read-Host

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
    # G-FOLD Guidance (Fuel-Optimal Powered Descent Guidance)
    #
    # Вместо заранее рассчитанных контрольных точек (гейтов, как в
    # программах P63-65 Apollo), оптимальная траектория пересчитывается
    # на каждом шаге симуляции (каждые 0.1 с).
    #
    # Ключевая идея G-FOLD: логарифмическая замена σ = ln(m) превращает
    # нелинейную зависимость тяги от убывающей массы в линейную.
    # Работаем с ускорением Γ = T/m, а не с тягой T — это автоматически
    # учитывает изменение массы при расходе топлива.
    #
    # Для одномерного случая выпуклая оптимизация даёт аналитическое
    # решение: при граничных условиях h → 0, v → v_f оптимальное
    # ускорение:
    #
    #   Γ = g + (v² − v_f²) / (2·h)
    #
    # Непрерывный пересчёт компенсирует любые отклонения: неравномерность
    # тяги, ошибки интегрирования, изменение массы, смену места посадки
    #

    # после срабатывания щупов прошивка не вмешивается — двигатель гасится штатно
    if (-not [Situation]::ContactLight) {

        $H = [Situation]::Height
        $V = [Situation]::Velocity
        $m = [Constants]::DryMass + [Situation]::FuelMass
        $g_moon = [Constants]::MoonGravity

        # Γ_max — максимальное ускорение от тяги при текущей массе
        # По мере выработки топлива m падает → Γ_max растёт
        $GammaMax = [Constants]::MaxThrust / $m

        # максимальное чистое замедление (тяга минус гравитация)
        $netDecel = $GammaMax - $g_moon

        $v_f = [Firmware]::TouchdownVelocity

        # ── Определяем, нужно ли начинать торможение ──

        $needBraking = $false

        if ([Situation]::EngineState -ne [EngineStatus]::Off) {
            # двигатель уже работает — продолжаем управление G-FOLD
            $needBraking = $true
        }
        elseif ($V -lt $v_f -and $netDecel -gt 0.01) {
            # двигатель выключен, падаем быстрее целевой скорости
            # прогнозируем состояние после задержки включения двигателя
            $td = [Constants]::IgnitionTime + [Constants]::ThrottleLag
            $V_pred = $V - $g_moon * $td
            $H_pred = $H + $V * $td - 0.5 * $g_moon * $td * $td

            if ($H_pred -le 0) {
                # за время включения упадём на поверхность — включаем немедленно
                $needBraking = $true
            }
            else {
                # минимальная высота торможения из прогнозной скорости
                $h_brake = ($V_pred * $V_pred) / (2.0 * $netDecel)

                if ($H_pred -le $h_brake * [Firmware]::SafetyMargin) {
                    $needBraking = $true
                }
            }
        }

        # Вычисляем команду тяги

        if ($needBraking -and $H -gt 0.5) {
            # G-FOLD: аналитическое решение выпуклой задачи
            #   Γ = g + (v² − v_f²) / (2·h)
            # При пересчёте каждые dt это эквивалентно непрерывному
            # решению SOCP с логарифмической заменой массы
            $GammaCmd = $g_moon + ($V * $V - $v_f * $v_f) / (2.0 * $H)

            # ограничиваем максимальным доступным ускорением
            if ($GammaCmd -gt $GammaMax) { $GammaCmd = $GammaMax }

            if ($GammaCmd -lt $g_moon * 0.3) {
                # ускорение слишком мало — скорость ниже целевой, тяга не нужна
                $pctRequired = 0.0
            }
            else {
                # переводим ускорение в тягу
                $pctRequired = ($GammaCmd * $m) * 100.0 / [Constants]::MaxThrust
            }
        }
        elseif ($needBraking -and $H -le 0.5) {
            # у поверхности — пропорциональное гашение к целевой скорости
            $GammaCmd = $g_moon + ($v_f - $V) / 0.5
            if ($GammaCmd -lt 0) { $GammaCmd = 0 }
            $pctRequired = ($GammaCmd * $m) * 100.0 / [Constants]::MaxThrust
        }
        else {
            # свободное падение — двигатель не нужен
            $pctRequired = 0.0
        }

        # Ограничения мёртвых зон двигателя DPS

        if ($pctRequired -lt [Constants]::MinThrustPct) {
            if (
                [Situation]::EngineState -eq [EngineStatus]::Off -or
                [Situation]::EngineState -eq [EngineStatus]::Ignition
            ) {
                $pctRequired = 0.0
            }
            else {
                # двигатель работает — ставим минимум, чтобы не заглох
                $pctRequired = [Constants]::MinThrustPct
            }
        }

        if ($pctRequired -gt [Constants]::MaxThrustPct) {
            # двигатель не может обеспечить такую тягу — ставим сразу максимум
            $pctRequired = 100.0
        }

        # Управление состоянием двигателя

        if ([Situation]::EngineState -eq [EngineStatus]::Off -and $pctRequired -gt 0.0) {
            # запускаем зажигание
            [Situation]::EngineState = [EngineStatus]::Ignition
            [Situation]::ThrustCommandedPct = $pctRequired
            [Situation]::TimeThrustStart = [Situation]::Time
            [Situation]::TimeThrustEnd = [Situation]::Time + [Constants]::IgnitionTime
            [Situation]::ThrustStart = [Situation]::Thrust
            [Situation]::ThrustEnd = [Constants]::MaxThrust * ($pctRequired / 100.0)
        }
        elseif ([Situation]::EngineState -eq [EngineStatus]::Ignition) {
            # во время зажигания не меняем команду — ждём выхода двигателя
        }
        elseif ([Math]::Abs($pctRequired - [Situation]::ThrustCommandedPct) -gt 2.0) {
            # значимое изменение тяги (>2%) — переходим в режим Throttling
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
Write-Host ("Время посадки:          {0,7:F2} с" -f ([Situation]::Time))  -ForegroundColor Green
Write-Host ("Скорость касания:       {0,7:F2} м/с" -f $RecordedTouchdownVelocity) -ForegroundColor Green
Write-Host ("Максимальная скорость:  {0,7:F2} м/с" -f $RecordedMaxVelocity) -ForegroundColor Green
Write-Host ("Расход топлива:         {0,7:F2} кг" -f ([Constants]::FuelStart - [Situation]::FuelMass)) -ForegroundColor Green
Write-Host ("Максимальное ускорение: {0,7:F2} g" -f $RecordedMaxAcceleration) -ForegroundColor Green
Write-Host ""

# Сохраняем телеметрию в файл
$logPath = Join-Path $PSScriptRoot "mode2a.log"
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("Time;Height;Velocity;ThrustPct;Acceleration;FuelMass;EngineState")
foreach ($r in $Telemetry) {
    $lines.Add(("{0:F1};{1:F1};{2:F1};{3:F1};{4:F1};{5:F1};{6}" -f $r.Time, $r.Height, $r.Velocity, $r.ThrustPct, $r.Acceleration, $r.FuelMass, $r.EngineState))
}
[System.IO.File]::WriteAllLines($logPath, $lines)
Write-Host ("Телеметрия сохранена: " + $logPath) -ForegroundColor Green


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
$g.Clear([System.Drawing.Color]::FromArgb(12, 14, 12))

# шрифты и кисти
$fontNormal = New-Object System.Drawing.Font("Fira Code", 16)
$fontSmall = New-Object System.Drawing.Font("Fira Code", 10)
$brushTitle = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 255, 120))
$brushAxis = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, 160, 60))
$brushDim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40, 100, 40))
$brushBright = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 255, 70))
$brushMid = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 200, 50))
$brushLight = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(100, 220, 100))
$brushPure = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 255, 0))

# перья для графиков
$penGrid = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(25, 40, 25), 1)
$penTick = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(35, 55, 35), 1)
$penOff = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(20, 40, 20), 2)
$penIgniting = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180, 255, 180), 4)
$penRunning = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 200, 50), 2)
$penFullThrust = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 255, 0), 2)
$penShutdown = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 140, 50), 2)
$penG = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 255, 70), 2)
$penMoonG = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 180, 0), 2)
$penMoonG.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash

# график 1: высота (с раскраской по состоянию двигателя)

$graphX = $marginLeft
$graphY = 30

# $graphWidth уже вычислен выше на основе времени посадки
$graphHeight = 240

$g.DrawRectangle($penGrid, $graphX, $graphY, $graphWidth, $graphHeight)
$g.DrawString("ВЫСОТА", $fontNormal, $brushTitle, $graphX, $graphY - 24)

# сетка для графика высоты
for ($i = 0; $i -le 5; $i++) {
    $yPos = $graphY + ($graphHeight / 5) * $i
    $g.DrawLine($penGrid, $graphX, $yPos, $graphX + $graphWidth, $yPos)
    $val = [Constants]::HeightStart - ([Constants]::HeightStart / 5) * $i
    $g.DrawString("{0:F0}м" -f $val, $fontSmall, $brushAxis, $graphX - 50, $yPos - 9)
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
$g.DrawString("СТАТИСТИКА ПОЛЁТА", $fontSmall, $brushTitle, $statsX, $statsY)
$g.DrawString(("Время:    {0,5:F1} сек" -f [Situation]::Time), $fontSmall, $brushBright, $statsX, $statsY + 18)
$g.DrawString(("Топливо:  {0,5:F1} кг" -f ([Constants]::FuelStart - [Situation]::FuelMass)), $fontSmall, $brushMid, $statsX, $statsY + 36)
$g.DrawString(("Макс g:   {0,5:F2} g" -f $RecordedMaxAcceleration), $fontSmall, $brushLight, $statsX, $statsY + 54)
$g.DrawString(("Макс V:   {0,5:F2} м/с" -f $RecordedMaxVelocity), $fontSmall, $brushBright, $statsX, $statsY + 72)
$g.DrawString(("Касание:  {0,5:F2} м/с" -f $RecordedTouchdownVelocity), $fontSmall, $brushBright, $statsX, $statsY + 90)

# легенда состояний двигателя
$legendX = $graphX + 30
$legendY = $graphY + $graphHeight - 90
$g.DrawLine($penOff, $legendX, $legendY, $legendX + 20, $legendY)
$g.DrawString("Выключен", $fontSmall, $brushDim, $legendX + 25, $legendY - 6)
$g.DrawLine($penIgniting, $legendX, $legendY + 15, $legendX + 20, $legendY + 15)
$g.DrawString("Зажигание", $fontSmall, $brushLight, $legendX + 25, $legendY + 9)
$g.DrawLine($penRunning, $legendX, $legendY + 30, $legendX + 20, $legendY + 30)
$g.DrawString("Регулируемая тяга", $fontSmall, $brushMid, $legendX + 25, $legendY + 24)
$g.DrawLine($penFullThrust, $legendX, $legendY + 45, $legendX + 20, $legendY + 45)
$g.DrawString("Полная тяга", $fontSmall, $brushPure, $legendX + 25, $legendY + 39)
$g.DrawLine($penShutdown, $legendX, $legendY + 60, $legendX + 20, $legendY + 60)
$g.DrawString("Гашение", $fontSmall, $brushDim, $legendX + 25, $legendY + 54)

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
$g.DrawString("g", $fontSmall, $brushAxis, $gGraphX + 5, $moonG_y - 18)

# рамка графика
$g.DrawRectangle($penGrid, $gGraphX, $gGraphY, $gGraphWidth, $gGraphHeight)

# заголовок графика
$g.DrawString("УСКОРЕНИЕ", $fontNormal, $brushTitle, $gGraphX, $gGraphY - 24)

# сетка (шаг 0.1g)
$gDivisions = [int]($gMaxVal * 10)
for ($i = 0; $i -le $gDivisions; $i++) {
    $yPos = $gGraphY + ($gGraphHeight / $gDivisions) * $i
    $g.DrawLine($penGrid, $gGraphX, $yPos, $gGraphX + $gGraphWidth, $yPos)
    $val = $gMaxVal - 0.1 * $i
    $g.DrawString("{0:F1}g" -f $val, $fontSmall, $brushAxis, $gGraphX - 50, $yPos - 9)
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

$outputPath = Join-Path $PSScriptRoot "mode2a.png"

try {
    $bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()

    if (Test-Path $outputPath) {
        Write-Host ("График сохранён: " + $outputPath) -ForegroundColor Green
    }
    else {
        Write-Host "Ошибка: файл не создан" -ForegroundColor DarkGreen
    }
}
catch {
    Write-Host ("Ошибка сохранения графика: " + $_.Exception.Message) -ForegroundColor DarkGreen
    $g.Dispose()
    $bmp.Dispose()
}

# Диаграмма 5

$g5imgWidth  = 600
$g5imgHeight = 400
$g5marginLeft   = 60
$g5marginRight  = 30
$g5marginTop    = 40
$g5marginBottom = 50

$g5graphWidth  = $g5imgWidth - $g5marginLeft - $g5marginRight
$g5graphHeight = $g5imgHeight - $g5marginTop - $g5marginBottom

# физика (для теоретической кривой)
$g5_g_moon   = [Constants]::MoonGravity
$g5_totalMass = [Constants]::DryMass + [Constants]::FuelStart
$g5_a_net = ([Constants]::MaxThrust / $g5_totalMass) - $g5_g_moon

# диапазон осей
$g5vMax = 80.0
$g5hMax = 1800.0

# создаём bitmap
$g5bmp = New-Object System.Drawing.Bitmap($g5imgWidth, $g5imgHeight)
$g5 = [System.Drawing.Graphics]::FromImage($g5bmp)
$g5.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g5.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# палитра
$g5colorBg        = [System.Drawing.Color]::FromArgb(12, 14, 12)
$g5colorGrid      = [System.Drawing.Color]::FromArgb(25, 40, 25)
$g5colorAxis      = [System.Drawing.Color]::FromArgb(0, 180, 0)
$g5colorCurve     = [System.Drawing.Color]::FromArgb(0, 255, 70)
$g5colorTitle     = [System.Drawing.Color]::FromArgb(120, 255, 120)
$g5colorZone      = [System.Drawing.Color]::FromArgb(0, 140, 50)
$g5colorDanger    = [System.Drawing.Color]::FromArgb(0, 255, 0)
$g5colorAxisLabel = [System.Drawing.Color]::FromArgb(60, 160, 60)
$g5colorTraj      = [System.Drawing.Color]::FromArgb(50, 255, 50)

# шрифты
$g5fontTitle  = New-Object System.Drawing.Font("Fira Code", 18, [System.Drawing.FontStyle]::Bold)
$g5fontZone   = New-Object System.Drawing.Font("Fira Code", 14, [System.Drawing.FontStyle]::Bold)
$g5fontAxis   = New-Object System.Drawing.Font("Fira Code", 12)
$g5fontLegend = New-Object System.Drawing.Font("Fira Code", 9)

# кисти и перья
$g5brushBg        = New-Object System.Drawing.SolidBrush($g5colorBg)
$g5brushTitle     = New-Object System.Drawing.SolidBrush($g5colorTitle)
$g5brushZone      = New-Object System.Drawing.SolidBrush($g5colorZone)
$g5brushDanger    = New-Object System.Drawing.SolidBrush($g5colorDanger)
$g5brushAxisLabel = New-Object System.Drawing.SolidBrush($g5colorAxisLabel)
$g5brushCurve     = New-Object System.Drawing.SolidBrush($g5colorCurve)
$g5brushTraj      = New-Object System.Drawing.SolidBrush($g5colorTraj)

$g5penGrid  = New-Object System.Drawing.Pen($g5colorGrid, 1)
$g5penAxis  = New-Object System.Drawing.Pen($g5colorAxis, 2)
$g5penCurve = New-Object System.Drawing.Pen($g5colorCurve, 3)
$g5penTraj  = New-Object System.Drawing.Pen($g5colorTraj, 3)
$g5penTraj.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash

# фон
$g5.FillRectangle($g5brushBg, 0, 0, $g5imgWidth, $g5imgHeight)

# функции координат
function G5VtoX([double]$v) {
    return $g5marginLeft + ($v / $g5vMax) * $g5graphWidth
}
function G5HtoY([double]$h) {
    return $g5marginTop + $g5graphHeight - ($h / $g5hMax) * $g5graphHeight
}

# сетка
for ($v = 0; $v -le $g5vMax; $v += 20) {
    $x = G5VtoX $v
    $g5.DrawLine($g5penGrid, $x, $g5marginTop, $x, ($g5marginTop + $g5graphHeight))
}
for ($h = 0; $h -le $g5hMax; $h += 400) {
    $y = G5HtoY $h
    $g5.DrawLine($g5penGrid, $g5marginLeft, $y, ($g5marginLeft + $g5graphWidth), $y)
}

# оси
$g5.DrawLine($g5penAxis, $g5marginLeft, ($g5marginTop + $g5graphHeight), ($g5marginLeft + $g5graphWidth), ($g5marginTop + $g5graphHeight))
$g5.DrawLine($g5penAxis, $g5marginLeft, $g5marginTop, $g5marginLeft, ($g5marginTop + $g5graphHeight))

# подписи осей
$g5sfCenter = New-Object System.Drawing.StringFormat
$g5sfCenter.Alignment = [System.Drawing.StringAlignment]::Center

$g5.DrawString("вертикальная скорость", $g5fontAxis, $g5brushAxisLabel,
    ($g5marginLeft + $g5graphWidth / 2), ($g5imgHeight - 36), $g5sfCenter)

$g5state = $g5.Save()
$g5.TranslateTransform(22, ($g5marginTop + $g5graphHeight / 2))
$g5.RotateTransform(-90)
$g5.DrawString("высота", $g5fontAxis, $g5brushAxisLabel, 0, 0, $g5sfCenter)
$g5.Restore($g5state)

# теоретическая кривая H = V² / (2·a_net)
$g5curvePoints = New-Object System.Collections.Generic.List[System.Drawing.PointF]
$g5step = 0.5
for ($v = 0; $v -le $g5vMax; $v += $g5step) {
    $h = ($v * $v) / (2.0 * $g5_a_net)
    if ($h -gt $g5hMax) { break }
    $px = G5VtoX $v
    $py = G5HtoY $h
    $g5curvePoints.Add([System.Drawing.PointF]::new($px, $py))
}
if ($g5curvePoints.Count -ge 2) {
    $g5.DrawLines($g5penCurve, $g5curvePoints.ToArray())
}

# траектория из телеметрии (пунктир)
$g5trajPoints = New-Object System.Collections.Generic.List[System.Drawing.PointF]
foreach ($r in $Telemetry) {
    $vAbs = [Math]::Abs($r.Velocity)
    if ($vAbs -le $g5vMax -and $r.Height -le $g5hMax) {
        $px = G5VtoX $vAbs
        $py = G5HtoY $r.Height
        $g5trajPoints.Add([System.Drawing.PointF]::new($px, $py))
    }
}
if ($g5trajPoints.Count -ge 2) {
    $g5.DrawLines($g5penTraj, $g5trajPoints.ToArray())
}

# надписи зон
$g5sfZone = New-Object System.Drawing.StringFormat
$g5sfZone.Alignment = [System.Drawing.StringAlignment]::Center

$g5.DrawString("безопасная зона", $g5fontZone, $g5brushZone,
    (G5VtoX 25), (G5HtoY 1200), $g5sfZone)
$g5.DrawString("катастрофа", $g5fontZone, $g5brushDanger,
    (G5VtoX 60), (G5HtoY 450), $g5sfZone)

# легенда
$g5legendX = $g5marginLeft + 15
$g5legendY = $g5marginTop + 10
$g5.DrawLine($g5penCurve, $g5legendX, ($g5legendY + 6), ($g5legendX + 25), ($g5legendY + 6))
$g5.DrawString("оптимальная кривая", $g5fontLegend, $g5brushCurve, ($g5legendX + 30), $g5legendY)
$g5.DrawLine($g5penTraj, $g5legendX, ($g5legendY + 22), ($g5legendX + 25), ($g5legendY + 22))
$g5.DrawString("телеметрия", $g5fontLegend, $g5brushTraj, ($g5legendX + 30), ($g5legendY + 16))

# заголовок
$g5.DrawString("Диаграмма посадки", $g5fontTitle, $g5brushTitle,
    ($g5marginLeft + 15), 8)

# сохранение
$g5outputPath = Join-Path $PSScriptRoot "graph5-gfold.png"
try {
    $g5bmp.Save($g5outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g5.Dispose()
    $g5bmp.Dispose()
    Write-Host ("График сохранён: " + $g5outputPath) -ForegroundColor Green
}
catch {
    Write-Host ("Ошибка сохранения графика: " + $_.Exception.Message) -ForegroundColor DarkGreen
    $g5.Dispose()
    $g5bmp.Dispose()
}