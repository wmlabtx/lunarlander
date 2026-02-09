enum EngineStatus {
  Off
  Ignition
  Throttling
  Active
  Cutoff
}

Add-Type -AssemblyName System.Drawing
. "$PSScriptRoot\functions.ps1"

# Тест Get-LMFuelFlow

Write-Host ""
Write-Host "Test Get-LMFuelFlow:" -ForegroundColor Cyan

# Реальные данные расхода топлива DPS LM-5 (кг/с)
$tests = @(
  @{ Pct = 0;  Expected = 0.0  }
  @{ Pct = 10; Expected = 1.70 }
  @{ Pct = 65; Expected = 10.1 }
  @{ Pct = 100; Expected = 15.3 }
)

$passed = 0
$failed = 0

foreach ($test in $tests) {
  $result = Get-LMFuelFlow $test.Pct
  $diff = [Math]::Abs($result - $test.Expected)
  $tolerance = 0.05

  if ($diff -le $tolerance) {
    Write-Host (" PASS {0,3}% -> {1,6:F4} (expected {2,5:F2})" -f $test.Pct, $result, $test.Expected) -ForegroundColor Green
    $passed++
  }
  else {
    Write-Host (" FAIL {0,3}% -> {1,6:F4} (expected {2,5:F2}, diff {3:F4})" -f $test.Pct, $result, $test.Expected, $diff) -ForegroundColor Red
    $failed++
  }
}

Write-Host ("Result: {0} passed, {1} failed" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })

# Тест Format-Bar

Write-Host ""
Write-Host "Test Format-Bar (width=20):" -ForegroundColor Cyan

@(0, 10, 25, 50, 75, 90, 100) | ForEach-Object {
  $bar = Format-Bar $_ 100 20
  Write-Host (" {0,3}% {1}" -f $_, $bar)
}

# Тест Get-ThrustEasing

Write-Host ""
Write-Host "Test Get-ThrustEasing (0 to 1560 N over 1s):" -ForegroundColor DarkGreen

$tStart = 0.0
$tEnd = 1.0
$thrStart = 0.0
$thrEnd = 1560.0

for ($time = 0.0; $time -le 1.001; $time += 0.1) {
  $thrust = Get-ThrustEasing $tStart $tEnd $time $thrStart $thrEnd
  $bar = Format-Bar $thrust $thrEnd 20
  $ratio = $thrust / $thrEnd
  $filled = [Math]::Round($ratio * 18)
  Write-Host (" t={0,4:F1}s T={1,7:F1} N [{2,2}/{3}] {4}" -f $time, $thrust, $filled, 18, $bar) -ForegroundColor Green
}

# Test Format-Scales

Write-Host ""
Write-Host "Test Format-Scales:" -ForegroundColor Cyan

$scaleTests = @(
  @{ Label = "Freefall (engine off)"; 
    Height = 3000.0; Velocity = -50.0; ThrustPct = 0; 
    Acceleration = 0.0; AccelerationMax = 1.0; FuelMass = 10500; EngineState = [EngineStatus]::Off }
  @{ Label = "Ignition";
    Height = 1500.0; Velocity = -80.0; ThrustPct = 0; Acceleration = 0.0; AccelerationMax = 1.0; FuelMass = 10500; 
    EngineState = [EngineStatus]::Ignition }
  @{ Label = "Active (throttled)";
    Height = 800.0; Velocity = -40.0; ThrustPct = 42; Acceleration = 0.7; AccelerationMax = 1.0; FuelMass = 8000; 
    EngineState = [EngineStatus]::Active }
  @{ Label = "Throttling";
    Height = 200.0; Velocity = -10.0; ThrustPct = 30; Acceleration = 0.5; AccelerationMax = 1.0; FuelMass = 6000; 
    EngineState = [EngineStatus]::Throttling }
  @{ Label = "Low altitude (warning)";
    Height = 5.0;  Velocity = -0.5; ThrustPct = 15; Acceleration = 0.2; AccelerationMax = 1.0; FuelMass = 150; 
    EngineState = [EngineStatus]::Active }
  @{ Label = "Cutoff";
    Height = 1.5;  Velocity = -0.3; ThrustPct = 10; Acceleration = 0.17; AccelerationMax = 1.0; FuelMass = 100; 
    EngineState = [EngineStatus]::Cutoff }
)

foreach ($test in $scaleTests) {
  Write-Host ""
  Write-Host (" {0}" -f $test.Label) -ForegroundColor DarkYellow
  Format-Scales `
    -Height $test.Height `
    -HeightMax 3000.0 `
    -Velocity $test.Velocity `
    -VelocityMax 100.0 `
    -ThrustPct $test.ThrustPct `
    -Acceleration $test.Acceleration `
    -AccelerationMax $test.AccelerationMax `
    -FuelMass $test.FuelMass `
    -FuelMassMax 10500 `
    -EngineState $test.EngineState
}
