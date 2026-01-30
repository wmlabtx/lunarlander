# Константы

$g_moon = 1.62          # лунное g (м/с²)
$g_earth = 9.80665      # земное g (м/с²)
$m_dry = 2000.0         # масса посадочного модуля без топлива (кг)
$v_e = 3050.0           # эффективная скорость истечения реактивной струи (м/с)
$t_max = 15000.0        # максимальная тяга двигателя (Н)
$t_min_pct = 10         # минимальная тяга двигателя (%)
$t_max_pct = 60         # максимально регулируемая тяга двигателя (%)
$t_step_pct = 5         # шаг изменения тяги двигателя (%)
$a_limit_earth_g = 3.0  # ограничение по перегрузке (в земных g)

# Стартовые условия

$h_start = 2000.0       # начальная высота (м)
$h_shutdown = 1.0       # высота отключения двигателя (м)
$v = 0.0                # начальная скорость (м/с)
$m_fuel_start = 1000.0  # начальная масса топлива (кг)
$t_pct_start = 0        # начальная тяга (%)
$t = 0.0                # время (сек)
$dt = 0.1               # шаг симуляции (сек)

# Параметры двигателя
$throttle_lag = 2.0       # задержка зажигания двигателя (сек)
$throttle_interval = 0.5  # минимальный интервал между изменениями тяги (сек)
$throttle_cooldown = 0.0  # таймер до следующего разрешённого изменения
$engine_state = "off"     # состояние: off / igniting / running
$ignition_timer = 0.0     # таймер зажигания
$t_pct = $t_pct_start     # текущая реальная тяга в процентах, целое число (0 - 100)


# Телеметрия и история

$history = [System.Collections.Generic.List[PSObject]]::new()
$max_g = 0.0
$max_v = 0.0

Clear-Host
Write-Host "Посадка на Луну: Режим 1: Ручное управление" -ForegroundColor Cyan
Read-Host -Prompt "Нажмите ENTER для начала посадки..."

# Функция для отрисовки шкалы

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
    [int]$filled = [int]($ratio * $widthInner)
    [int]$empty = $widthInner - $filled

    if ($filled -gt 0) {
        $bar = [char]0xEE03  # начало заполненной шкалы
    } else {
        $bar = [char]0xEE00  # начало пустой шкалы
    }

    $bar += [string]([char]0xEE04) * $filled # заполненные блоки
    $bar += [string]([char]0xEE01) * $empty  # пустые блоки

    if ($ratio -eq 1.0) {
        $bar += [char]0xEE05  # конец полностью заполненной шкалы
    } else {
        $bar += [char]0xEE02  # конец пустой/частично заполненной шкалы
    }

    return $bar
}

# Функция целевой скорости (V_target) в зависимости от высоты (h)
# Использует параметрическую кубическую интерполяцию через три точки

function Get-TargetVelocity($currentH) {
    # Опорные точки (высота, скорость)
    $h_high = 2300.0      # приближение
    $h_mid  = 150.0       # ориентировка
    $h_low = 10.0         # торможение
    $h_landing = 
    

    $v_high = -45.0       # быстрое снижение
    $v_mid  = -4.5        # замедление
    $v_landing = -0.7     # скорость касания

    # Граничные условия
    if ($currentH -ge $h_high) { return $v_high }
    if ($currentH -le $h_landing) { return $v_landing }

    # Нормализуем высоту к параметру t ∈ [0, 1]
    # t=0 при h_landing, t=1 при h_high
    $t = ($currentH - $h_landing) / ($h_high - $h_landing)

    # Параметр средней точки
    $t_mid = ($h_mid - $h_landing) / ($h_high - $h_landing)

    # Наклон в средней точке (Catmull-Rom): dv/dt = (v_high - v_landing) / (1 - 0)
    $slope_mid = $v_high - $v_landing

    # Кусочная кубическая интерполация Hermite
    # Тангенсы масштабируются по длине сегмента в локальных координатах
    if ($t -le $t_mid) {
        # Нижний сегмент: от landing до mid
        $t_local = $t / $t_mid
        $h0 = $v_landing
        $h1 = $v_mid
        $m0 = 0                      # нулевой наклон внизу (плавный заход)
        $m1 = $slope_mid * $t_mid    # масштабированный тангенс
    } else {
        # Верхний сегмент: от mid до high
        $t_local = ($t - $t_mid) / (1 - $t_mid)
        $h0 = $v_mid
        $h1 = $v_high
        $m0 = $slope_mid * (1 - $t_mid)  # масштабированный тангенс
        $m1 = 0                           # нулевой наклон вверху
    }

    $t2 = $t_local * $t_local
    $t3 = $t2 * $t_local

    $h00 = 2*$t3 - 3*$t2 + 1
    $h10 = $t3 - 2*$t2 + $t_local
    $h01 = -2*$t3 + 3*$t2
    $h11 = $t3 - $t2

    return $h00 * $h0 + $h10 * $m0 + $h01 * $h1 + $h11 * $m1
}

# Симуляция посадки

$h = $h_start
$m_fuel = $m_fuel_start

[Console]::CursorVisible = $false
while ($h -gt 0) {
    $m_total = $m_dry + $m_fuel

    # Определяем желаемую скорость на основе высоты
    $v_target = Get-TargetVelocity $h
    # Плавно подгоняем реальную скорость под целевую
    $velocity_error = $v_target - $v

    # Расчет тяги для компенсации веса
    $hover_thrust = $m_total * $g_moon

    # Добавочная тяга для изменения скорости
    $kp = 2500.0  # "Чувствительность рук пилота"
    $required_thrust = $hover_thrust + ($velocity_error * $kp)

    # В целых долях (0-100)
    [int]$t_pct_target = [Math]::Round($required_thrust * 100 / $t_max)

    # Если требуется малая или нулевая тяга или рядом с поверхностью - выключаем двигатель
    if ($t_pct_target -eq 0 -or $t_pct_target -lt $t_min_pct -or $h -le $h_shutdown) {
        # Выключаем двигатель без задержки
        $t_pct_target = 0
    }
    else {
        if ($t_pct -eq 0) {
            # Первое включение двигателя после зажигания - начинаем с минимума $t_min_pct
            $t_pct_target = $t_min_pct
        }
        else {
            if ($t_pct -eq 100) {
                # Если текущая тяга 100%, а нужно меньше, снижаем сразу до $t_max_pct
                if ($t_pct_target -lt $t_max_pct) {
                    $t_pct_target = $t_max_pct
                }
                else {
                    # Если нужно больше 100%, остаёмся на 100%
                    $t_pct_target = 100
                }
            }
            else {
                if ($t_pct -eq $t_max_pct) {
                    # Если текущая тяга $t_max_pct, а нужно больше, переходим на 100%
                    if ($t_pct_target -gt $t_max_pct) {
                        $t_pct_target = 100
                    }
                    else {
                        $t_delta = [Math]::Min($t_pct - $t_pct_target, $t_step_pct)
                        $t_pct_target = $t_pct - $t_delta
                    }
                }
                else {
                    # Текущая тяга между $t_min_pct и $t_max_pct
                    if ($t_pct_target -gt $t_max_pct) {
                        # Нужно больше $t_max_pct, целимся сначала в $t_max_pct
                        $t_pct_target = $t_max_pct
                    }

                    if ($t_pct_target -gt $t_pct) {
                        # Нужно увеличить тягу
                        $t_delta = [Math]::Min($t_pct_target - $t_pct, $t_step_pct)
                        $t_pct_target = $t_pct + $t_delta
                    }
                    else {
                        # Нужно уменьшить тягу
                        $t_delta = [Math]::Min($t_pct - $t_pct_target, $t_step_pct)
                        $t_pct_target = $t_pct - $t_delta
                    }
                }
            }
        }
    }

    # Устанавливаем команду управления двигателем
    # Выключение - всегда мгновенно, изменение тяги - не чаще $throttle_interval
    if ($t_pct_target -eq 0) {
        $t_pct_commanded = 0
        $throttle_cooldown = 0.0
    } elseif ($throttle_cooldown -le 0) {
        $t_pct_commanded = $t_pct_target
        $throttle_cooldown = $throttle_interval
    }
    $throttle_cooldown -= $dt

    if ($m_fuel -le 0) { 
        # Нет топлива - двигатель выключен
        $t_pct_commanded = 0; 
        $m_fuel = 0; 
    }

    # Симуляция состояний двигателя с задержкой зажигания
    if ($t_pct_commanded -gt 0) {
        if ($engine_state -eq "off") {
            # Начинаем зажигание
            $engine_state = "igniting"
            $ignition_timer = 0.0
        } elseif ($engine_state -eq "igniting") {
            # Процесс зажигания
            $ignition_timer += $dt
            if ($ignition_timer -ge $throttle_lag) {
                $engine_state = "running"
            }
        }
    } else {
        # Команда на выключение
        $engine_state = "off"
        $ignition_timer = 0.0
    }

    # На самом деле реальная тяга зависит от состояния двигателя
    if ($engine_state -eq "running") {
        $t_pct = $t_pct_commanded
    } else {
        $t_pct = 0
    }

    $t_current = ($t_pct / 100.0) * $t_max
    $dm = ($t_current / $v_e) * $dt
    $m_fuel -= $dm

    $a_current = ($t_current / $m_total) - $g_moon
    $v += $a_current * $dt
    $h += $v * $dt
    $t += $dt

    # Сохранение телеметрии

    $g_force = ($t_current / $m_total) / $g_earth
    if ($g_force -gt $max_g) { $max_g = $g_force }

    $v_abs = [Math]::Abs($v)
    if ($v_abs -gt $max_v) { $max_v = $v_abs }

    $history.Add([PSCustomObject]@{
        Time = $t; Height = $h; Velocity = $v; Thrust = $t_pct; G = $g_force; Fuel = $m_fuel; EngineState = $engine_state
    })

    [Console]::SetCursorPosition(0, 1)

    $color = if ($h -lt 10) { "Red" } elseif ($h -lt 150) { "Yellow" } else { "White" }
    Write-Host ("ВЫСОТА:     {0,6:F1} м   " -f $h) -NoNewline -ForegroundColor $color
    $hBar = Format-Bar $h $h_start 15
    Write-Host $hBar -ForegroundColor $color

    $vAbs = [Math]::Abs($v)
    $color = if ($vAbs -gt 100) { "Red" } elseif ($vAbs -gt 45) { "Yellow" } else { "White" }
    Write-Host ("СКОРОСТЬ:   {0,6:F1} м/с " -f $v) -NoNewline -ForegroundColor $color
    $vBar = Format-Bar $vAbs 60.0 15
    Write-Host $vBar -ForegroundColor $color

    $color = if ($t_pct -lt 10) { "White" } elseif ($t_pct -le 60) { "Yellow" } else { "Red" }
    Write-Host ("ТЯГА:       {0,6:F1}%    " -f ($t_pct)) -NoNewline -ForegroundColor $color
    $tBar = Format-Bar $t_pct 100.0 15
    Write-Host $tBar -ForegroundColor $color

    $color = if ($g_force -gt 2.0) { "Red" } elseif ($g_force -gt 0.5) { "Yellow" } else { "White" }
    Write-Host ("УСКОРЕНИЕ:  {0,6:F2} g   " -f $g_force) -NoNewline -ForegroundColor $color
    $gBar = Format-Bar $g_force ($a_limit_earth_g + 0.5) 15
    Write-Host $gBar -ForegroundColor $color

    $color = if ($m_fuel -lt 200) { "Red" } elseif ($m_fuel -lt 500) { "Yellow" } else { "White" }
    Write-Host ("ТОПЛИВО:    {0,6:F0} кг  " -f $m_fuel) -NoNewline -ForegroundColor $color
    $fBar = Format-Bar $m_fuel $m_fuel_start 15
    Write-Host $fBar -ForegroundColor $color

    Write-Host "ДВИГАТЕЛЬ: " -NoNewline -ForegroundColor White
    if ($engine_state -eq "running") {
        Write-Host ([char]0x25CF + " Работает ") -ForegroundColor Green
    } elseif ($engine_state -eq "igniting") {
        Write-Host ([char]0x25D0 + " Зажигание") -ForegroundColor Yellow
    } else {
        Write-Host ([char]0x25CB + " Выключен ") -ForegroundColor DarkGray
    }

    Start-Sleep -Milliseconds 20
}

[Console]::CursorVisible = $true

Write-Host ("Скорость в момент посадки: {0,7:F2} м/с" -f $v)
Write-Host ("Максимальная скорость:     {0,7:F2} м/с" -f $max_v)
Write-Host ("Посадка заняла:            {0,7:F2} сек" -f $t)
Write-Host ("Израсходовано топлива:     {0,7:F2} кг" -f ($m_fuel_start - $m_fuel))
Write-Host ("Максимальное ускорение:    {0,7:F2} g" -f $max_g)

# Генерация PNG графика телеметрии

Write-Host "`nГенерация графика..." -ForegroundColor Cyan

Add-Type -AssemblyName System.Drawing

# Вычисляем ширину графика на основе времени посадки
# Каждая секунда = $pps пикселей
$pps = 3
$graphWidth = [int]($t * $pps)

# Отступы
$marginLeft = 60   # для подписей оси Y
$marginRight = 20  # минимальный отступ справа
$marginBottom = 30 # для подписей оси X

# Общая ширина и высота изображения
$imgWidth = $graphWidth + $marginLeft + $marginRight
$imgHeight = 510 + $marginBottom  # последний график заканчивается на y=510 (430+80)

# Создаём bitmap и graphics
$bmp = New-Object System.Drawing.Bitmap($imgWidth, $imgHeight)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Фон
$g.Clear([System.Drawing.Color]::FromArgb(20, 30, 40))

# Шрифты и кисти
$fontNormal = New-Object System.Drawing.Font("Consolas",16)
$fontSmall = New-Object System.Drawing.Font("Consolas", 10)
$brushWhite = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$brushGray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Gray)
$brushDarkGray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::DarkGray)
$brushGreen = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::LimeGreen)
$brushCyan = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Cyan)
$brushYellow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Yellow)
$brushRed = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Red)

# Перья для графиков
$penGrid = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50, 60, 70), 1)
$penTick = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40, 50, 55), 1)
$penOff = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 60, 60), 2)
$penIgniting = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 4)
$penRunning = New-Object System.Drawing.Pen([System.Drawing.Color]::Yellow, 2)
$penFullThrust = New-Object System.Drawing.Pen([System.Drawing.Color]::Red, 2)
$penThrust = New-Object System.Drawing.Pen([System.Drawing.Color]::Cyan, 2)
$penG = New-Object System.Drawing.Pen([System.Drawing.Color]::LimeGreen, 2)
$penMoonG = New-Object System.Drawing.Pen([System.Drawing.Color]::Orange, 2)
$penMoonG.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash

# Функция рисования оси времени (мелкие засечки + крупные с подписями)
function New-TimeAxis {
    param($graphics, $x, $y, $width, $height, $tTotal)

    # Мелкие засечки каждую секунду (короткие линии снизу графика)
    for ($ts = 1; $ts -lt $tTotal; $ts++) {
        $xPos = $x + ($ts / $tTotal) * $width
        $graphics.DrawLine($penTick, $xPos, $y + $height - 4, $xPos, $y + $height)
    }

    # Сетка каждые 10 секунд
    for ($ts = 10; $ts -lt $tTotal; $ts += 10) {
        $xPos = $x + ($ts / $tTotal) * $width
        $graphics.DrawLine($penTick, $xPos, $y, $xPos, $y + $height)
    }

    # Крупные засечки с подписями каждые 10 секунд
    for ($ts = 10; $ts -lt $tTotal; $ts += 10) {
        $xPos = $x + ($ts / $tTotal) * $width
        $graphics.DrawLine($penGrid, $xPos, $y, $xPos, $y + $height)
        $graphics.DrawString("{0:F0}" -f $ts, $fontSmall, $brushGray, $xPos - 10, $y + $height + 2)
    }
}

# Функция для рисования графика

function New-Graph {
    param(
        $graphics, $data, $property, $x, $y, $width, $height,
        $minVal, $maxVal, $pen, $title, $unit
    )

    # Рамка графика

    $graphics.DrawRectangle($penGrid, $x, $y, $width, $height)

    # Заголовок графика

    $graphics.DrawString($title, $fontNormal, $brushWhite, $x, $y - 24)

    # Сетка

    for ($i = 0; $i -le 5; $i++) {
        $yPos = $y + ($height / 5) * $i
        $graphics.DrawLine($penGrid, $x, $yPos, $x + $width, $yPos)
        $val = $maxVal - (($maxVal - $minVal) / 5) * $i
        $graphics.DrawString("{0:F1}$unit" -f $val, $fontSmall, $brushGray, $x - 50, $yPos - 9)
    }

    # Извлекаем значения

    $points = $data | Select-Object -ExpandProperty $property
    $timePoints = $data | Select-Object -ExpandProperty Time

    if ($points.Count -lt 2) { return }

    # Метки по оси X (секунды)
    New-TimeAxis $graphics $x $y $width $height $timePoints[-1]

    $range = $maxVal - $minVal
    if ($range -eq 0) { $range = 1 }

    # Рисуем линию графика

    for ($i = 0; $i -lt ($points.Count - 1); $i++) {
        $t1 = $timePoints[$i]
        $t2 = $timePoints[$i + 1]
        $v1 = $points[$i]
        $v2 = $points[$i + 1]

        $x1 = $x + ($t1 / $timePoints[-1]) * $width
        $x2 = $x + ($t2 / $timePoints[-1]) * $width
        $y1 = $y + $height - (($v1 - $minVal) / $range) * $height
        $y2 = $y + $height - (($v2 - $minVal) / $range) * $height

        $graphics.DrawLine($pen, $x1, $y1, $x2, $y2)
    }
}

# График 1: Высота (с раскраской по состоянию двигателя)

$graphX = $marginLeft
$graphY = 30
# $graphWidth уже вычислен выше на основе времени посадки
$graphHeight = 240

$g.DrawRectangle($penGrid, $graphX, $graphY, $graphWidth, $graphHeight)
$g.DrawString("ВЫСОТА", $fontNormal, $brushWhite, $graphX, $graphY - 24)

# Сетка для графика высоты
for ($i = 0; $i -le 5; $i++) {
    $yPos = $graphY + ($graphHeight / 5) * $i
    $g.DrawLine($penGrid, $graphX, $yPos, $graphX + $graphWidth, $yPos)
    $val = $h_start - ($h_start / 5) * $i
    $g.DrawString("{0:F0}м" -f $val, $fontSmall, $brushGray, $graphX - 50, $yPos - 9)
}

# Ось времени для графика высоты
$tTotal = ($history | Select-Object -ExpandProperty Time)[-1]
New-TimeAxis $g $graphX $graphY $graphWidth $graphHeight $tTotal

# Рисуем линию высоты с раскраской по состоянию двигателя

$points = $history | Select-Object -ExpandProperty Height
$timePoints = $history | Select-Object -ExpandProperty Time
$engineStates = $history | Select-Object -ExpandProperty EngineState
$thrustValues = $history | Select-Object -ExpandProperty Thrust

for ($i = 0; $i -lt ($points.Count - 1); $i++) {
    $t1 = $timePoints[$i]
    $t2 = $timePoints[$i + 1]
    $h1 = $points[$i]
    $h2 = $points[$i + 1]
    $state = $engineStates[$i]
    $thrust = $thrustValues[$i]

    $x1 = $graphX + ($t1 / $timePoints[-1]) * $graphWidth
    $x2 = $graphX + ($t2 / $timePoints[-1]) * $graphWidth
    $y1 = $graphY + $graphHeight - ($h1 / $h_start) * $graphHeight
    $y2 = $graphY + $graphHeight - ($h2 / $h_start) * $graphHeight

    # Выбираем перо в зависимости от состояния двигателя и тяги

    $pen = $penOff
    if ($state -eq "igniting") {
        $pen = $penIgniting
    }
    elseif ($state -eq "running") {
        if ($thrust -eq 100) {
            $pen = $penFullThrust
        } else {
            $pen = $penRunning
        }
    }

    $g.DrawLine($pen, $x1, $y1, $x2, $y2)
}

# Статистика в правом верхнем углу графика высоты

$statsX = $graphX + $graphWidth - 200
$statsY = $graphY + 10
$g.DrawString("СТАТИСТИКА ПОЛЁТА", $fontSmall, $brushWhite, $statsX, $statsY)
$g.DrawString(("Время:    {0,5:F1} сек" -f $t), $fontSmall, $brushGreen, $statsX, $statsY + 18)
$g.DrawString(("Топливо:  {0,5:F1} кг" -f ($m_fuel_start - $m_fuel)), $fontSmall, $brushCyan, $statsX, $statsY + 36)
$g.DrawString(("Макс g:   {0,5:F2} g" -f $max_g), $fontSmall, $brushYellow, $statsX, $statsY + 54)
$g.DrawString(("Макс V:   {0,5:F2} м/с" -f $max_v), $fontSmall, $brushWhite, $statsX, $statsY + 72)
$g.DrawString(("Касание:  {0,5:F2} м/с" -f $v), $fontSmall, $brushWhite, $statsX, $statsY + 90)

# Легенда состояний двигателя

$legendX = $graphX + 10
$legendY = $graphY + $graphHeight - 75
$g.DrawLine($penOff, $legendX, $legendY, $legendX + 20, $legendY)
$g.DrawString("Выключен", $fontSmall, $brushDarkGray, $legendX + 25, $legendY - 6)
$g.DrawLine($penIgniting, $legendX, $legendY + 15, $legendX + 20, $legendY + 15)
$g.DrawString("Зажигание", $fontSmall, $brushWhite, $legendX + 25, $legendY + 9)
$g.DrawLine($penRunning, $legendX, $legendY + 30, $legendX + 20, $legendY + 30)
$g.DrawString("Работает", $fontSmall, $brushYellow, $legendX + 25, $legendY + 24)
$g.DrawLine($penFullThrust, $legendX, $legendY + 45, $legendX + 20, $legendY + 45)
$g.DrawString("Полная тяга", $fontSmall, $brushRed, $legendX + 25, $legendY + 39)

# График 2: Тяга

New-Graph $g $history "Thrust" $marginLeft 310 $graphWidth 80 0 100.0 $penThrust "ТЯГА" "%"

# График 3: Ускорение

# Рисуем линию лунного g (до отрисовки самого графика)
$gGraphX = $marginLeft
$gGraphY = 430
$gGraphWidth = $graphWidth
$gGraphHeight = 80
$gMinVal = 0
# Округляем до одной цифры после запятой в большую сторону
$gMaxVal = [Math]::Ceiling($max_g * 10) / 10
$gRange = $gMaxVal - $gMinVal

# Вычисляем Y-координату для линии лунного g
# Переводим лунное g из м/с² в земные g
$moonG_in_earth_g = $g_moon / $g_earth
$moonG_normalized = ($moonG_in_earth_g - $gMinVal) / $gRange
$moonG_y = $gGraphY + $gGraphHeight - ($moonG_normalized * $gGraphHeight)

# Рисуем пунктирную линию
$g.DrawLine($penMoonG, $gGraphX, $moonG_y, $gGraphX + $gGraphWidth, $moonG_y)

# Подпись "Лунное g"
$g.DrawString("g", $fontSmall, $brushGray, $gGraphX + 5, $moonG_y - 18)

New-Graph $g $history "G" $gGraphX $gGraphY $gGraphWidth $gGraphHeight $gMinVal $gMaxVal $penG "УСКОРЕНИЕ" "g"

# Сохранение
$outputPath = Join-Path $PSScriptRoot "mode1.png"

try {
    $bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)

    # Очистка
    $g.Dispose()
    $bmp.Dispose()

    if (Test-Path $outputPath) {
        Write-Host ("График сохранён: " + $outputPath) -ForegroundColor Green

        # Открыть файл (опционально)
        # Start-Process $outputPath
    } else {
        Write-Host "Ошибка: файл не был создан" -ForegroundColor Red
    }
} catch {
    Write-Host ("Ошибка при сохранении графика: " + $_.Exception.Message) -ForegroundColor Red
    $g.Dispose()
    $bmp.Dispose()
}