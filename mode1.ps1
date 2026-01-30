# Константы

$g_moon = 1.62          # лунное g (м/с²)
$g_earth = 9.80665      # земное g (м/с²)
$m_dry = 2000.0         # масса посадочного модуля без топлива (кг)
$v_e = 3050.0           # эффективная скорость истечения реактивной струи (м/с)
$T_max = 15000.0        # максимальная тяга двигателя (Н)
$a_limit_earth_g = 3.0  # ограничение по перегрузке (в земных g)

# Стартовые условия

$h_start = 1000.0       # начальная высота (м)
$v = 0.0                # начальная скорость (м/с)
$m_fuel_start = 1000.0  # начальная масса топлива (кг)
$t = 0.0                # время (сек)
$dt = 0.1               # шаг симуляции (сек)

# Параметры двигателя
$throttle_lag = 2.0     # задержка зажигания двигателя (сек)
$engine_state = "off"   # состояние: off / igniting / running
$ignition_timer = 0.0   # таймер зажигания
$thrust_pct = 0.0       # реальная тяга (0.0 - 1.0)

# Телеметрия и история

$history = [System.Collections.Generic.List[PSObject]]::new()
$max_g = 0.0

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

# Симуляция посадки

$h = $h_start
$m_fuel = $m_fuel_start

[Console]::CursorVisible = $false
while ($h -gt 0) {
    $m_total = $m_dry + $m_fuel

    # Определяем целевую скорость на основе формулы оптимального торможения
    # v = sqrt(2*g*h) * коэффициент (0.3 = более агрессивное снижение)
    $v_target = -[Math]::Sqrt(2.0 * $g_moon * ($h + 0.5)) * 0.3

    # Вычисляем КОМАНДНУЮ тягу от автопилота
    if ($v -gt $v_target) {
        $thrust_pct_commanded = 0.0
    } else {
        # Вычисляем ошибку скорости
        $verror = $v_target - $v

        # Вычисляем необходимую тягу
        $hover_thrust = $m_total * $g_moon

        # Добавляем пропорциональную тягу
        $kp = 1800.0
        $target_thrust = $hover_thrust + ($verror * $kp)

        # Ограничение макс перегрузка 1g
        $t_limit_g = $m_total * (1.0 * $g_earth + $g_moon)

        $final_thrust = [Math]::Min($target_thrust, $T_max)
        $final_thrust = [Math]::Min($final_thrust, $t_limit_g)

        $thrust_pct_commanded = [Math]::Max(0.0, $final_thrust / $T_max)
    }

    if ($m_fuel -le 0) { $thrust_pct_commanded = 0; $m_fuel = 0 }

    # Симуляция состояний двигателя с задержкой зажигания
    if ($thrust_pct_commanded -gt 0.01) {
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
        $thrust_pct = $thrust_pct_commanded
    } else {
        $thrust_pct = 0.0
    }

    $T_current = $thrust_pct * $T_max
    $dm = ($T_current / $v_e) * $dt
    $m_fuel -= $dm

    $a_current = ($T_current / $m_total) - $g_moon
    $v += $a_current * $dt
    $h += $v * $dt
    $t += $dt

    # Сохранение телеметрии

    $g_force = ($T_current / $m_total) / $g_earth
    if ($g_force -gt $max_g) { $max_g = $g_force }

    $history.Add([PSCustomObject]@{
        Time = $t; Height = $h; Velocity = $v; Thrust = $thrust_pct; G = $g_force; Fuel = $m_fuel; EngineState = $engine_state
    })

    [Console]::SetCursorPosition(0, 1)

    $color = if ($h -lt -50) { "Red" } elseif ($v -lt -100) { "Yellow" } else { "Green" }
    Write-Host ("ВЫСОТА:     {0,6:F1} м   " -f $h) -NoNewline -ForegroundColor $color
    $hBar = Format-Bar $h $h_start 15
    Write-Host $hBar -ForegroundColor $color

    $vAbs = [Math]::Abs($v)
    $color = if ($vAbs -lt -50) { "Red" } elseif ($vAbs -lt -20) { "Yellow" } else { "Green" }
    Write-Host ("СКОРОСТЬ:   {0,6:F1} м/с " -f $v) -NoNewline -ForegroundColor $color
    $vBar = Format-Bar $vAbs $m_fuel_start 15
    Write-Host $vBar -ForegroundColor $color

    $color = if ($thrust_pct -lt 0.1) { "White" } elseif ($thrust_pct -lt 0.9) { "Yellow" } else { "Red" }
    Write-Host ("ТЯГА:       {0,6:F1}%    " -f ($thrust_pct*100)) -NoNewline -ForegroundColor $color
    $tBar = Format-Bar $thrust_pct 1.0 15
    Write-Host $tBar -ForegroundColor $color

    $color = if ($g_force -gt 2.0) { "Red" } elseif ($g_force -gt 0.5) { "Green" } else { "White" }
    Write-Host ("ПЕРЕГРУЗКА: {0,6:F2} g   " -f $g_force) -NoNewline -ForegroundColor $color
    $gBar = Format-Bar $g_force ($a_limit_earth_g + 0.5) 15
    Write-Host $gBar -ForegroundColor $color

    $color = if ($m_fuel -lt 200) { "Red" } elseif ($m_fuel -lt 500) { "Yellow" } else { "Green" }
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
Write-Host ("Посадка заняла:            {0,7:F2} сек" -f $t)
Write-Host ("Израсходовано топлива:     {0,7:F2} кг" -f ($m_fuel_start - $m_fuel))
Write-Host ("Максимальная перегрузка:   {0,7:F2} g" -f $max_g)

# Генерация PNG графика телеметрии

Write-Host "`nГенерация графика..." -ForegroundColor Cyan

Add-Type -AssemblyName System.Drawing

$imgWidth = 800
$imgHeight = 600
$margin = 60

# Создаём bitmap и graphics
$bmp = New-Object System.Drawing.Bitmap($imgWidth, $imgHeight)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Фон
$g.Clear([System.Drawing.Color]::FromArgb(20, 30, 40))

# Шрифты и кисти
$fontNormal = New-Object System.Drawing.Font("Consolas",16)
$fontSmall = New-Object System.Drawing.Font("Consolas", 12)
$brushWhite = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$brushGray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Gray)
$brushDarkGray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, 60, 60))
$brushGreen = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::LimeGreen)
$brushCyan = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Cyan)
$brushYellow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Yellow)

# Перья для графиков
$penGrid = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50, 60, 70), 1)
$penOff = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 60, 60), 2)
$penIgniting = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3)
$penRunning = New-Object System.Drawing.Pen([System.Drawing.Color]::Yellow, 2)
$penThrust = New-Object System.Drawing.Pen([System.Drawing.Color]::Cyan, 2)
$penG = New-Object System.Drawing.Pen([System.Drawing.Color]::LimeGreen, 2)

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

$graphX = $margin
$graphY = 30
$graphWidth = $imgWidth - 2*$margin
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

# Рисуем линию высоты с раскраской по состоянию двигателя

$points = $history | Select-Object -ExpandProperty Height
$timePoints = $history | Select-Object -ExpandProperty Time
$engineStates = $history | Select-Object -ExpandProperty EngineState

for ($i = 0; $i -lt ($points.Count - 1); $i++) {
    $t1 = $timePoints[$i]
    $t2 = $timePoints[$i + 1]
    $h1 = $points[$i]
    $h2 = $points[$i + 1]
    $state = $engineStates[$i]

    $x1 = $graphX + ($t1 / $timePoints[-1]) * $graphWidth
    $x2 = $graphX + ($t2 / $timePoints[-1]) * $graphWidth
    $y1 = $graphY + $graphHeight - ($h1 / $h_start) * $graphHeight
    $y2 = $graphY + $graphHeight - ($h2 / $h_start) * $graphHeight

    # Выбираем цвет в зависимости от состояния двигателя

    $pen = $penOff
    if ($state -eq "igniting") { $pen = $penIgniting }
    elseif ($state -eq "running") { $pen = $penRunning }

    $g.DrawLine($pen, $x1, $y1, $x2, $y2)
}

# Статистика в правом верхнем углу графика высоты

$statsX = $graphX + $graphWidth - 200
$statsY = $graphY + 10
$g.DrawString("СТАТИСТИКА ПОЛЁТА", $fontSmall, $brushWhite, $statsX, $statsY)
$g.DrawString(("Время:    {0,5:F1} сек" -f $t), $fontSmall, $brushGreen, $statsX, $statsY + 18)
$g.DrawString(("Топливо:  {0,5:F1} кг" -f ($m_fuel_start - $m_fuel)), $fontSmall, $brushCyan, $statsX, $statsY + 36)
$g.DrawString(("Макс g:   {0,5:F2} g" -f $max_g), $fontSmall, $brushYellow, $statsX, $statsY + 54)
$g.DrawString(("Скорость: {0,5:F2} м/с" -f $v), $fontSmall, $brushWhite, $statsX, $statsY + 72)

# Легенда состояний двигателя

$legendX = $graphX + 10
$legendY = $graphY + $graphHeight - 60
$g.DrawLine($penOff, $legendX, $legendY, $legendX + 20, $legendY)
$g.DrawString("Выключен", $fontSmall, $brushDarkGray, $legendX + 25, $legendY - 6)
$g.DrawLine($penIgniting, $legendX, $legendY + 15, $legendX + 20, $legendY + 15)
$g.DrawString("Зажигание", $fontSmall, $brushWhite, $legendX + 25, $legendY + 9)
$g.DrawLine($penRunning, $legendX, $legendY + 30, $legendX + 20, $legendY + 30)
$g.DrawString("Работает", $fontSmall, $brushYellow, $legendX + 25, $legendY + 24)

# График 2: Тяга

New-Graph $g $history "Thrust" $margin 310 ($imgWidth - 2*$margin) 80 0 1.0 $penThrust "ТЯГА" "%"

# График 3: Перегрузка

New-Graph $g $history "G" $margin 430 ($imgWidth - 2*$margin) 80 0 ([Math]::Ceiling($max_g * 1.2)) $penG "ПЕРЕГРУЗКА" "g"

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